import AppKit
import Common

struct FocusCommand: Command {
    let args: FocusCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        if let window = target.windowOrNil, await shouldFailBecauseFullscreen_nonCancellable(
            window: window,
            failIfFullscreen: args.failIfFullscreen,
            failIfMacosNativeFullscreen: args.failIfMacosNativeFullscreen,
        ) {
            return .fail
        }
        // todo bug: floating windows break mru
        let floatingWindows = args.floatingAsTiling ? await makeFloatingWindowsSeenAsTiling(workspace: target.workspace) : []
        defer {
            if args.floatingAsTiling {
                restoreFloatingWindows(floatingWindows: floatingWindows, workspace: target.workspace)
            }
        }

        switch args.target {
            case .direction(let direction):
                let window = target.windowOrNil
                if let (parent, ownIndex) = window?.closestParent(hasChildrenInDirection: direction, withLayout: nil) {
                    guard let windowToFocus = parent.children[ownIndex + direction.focusOffset]
                        .findLeafWindowRecursive(snappedTo: direction.opposite) else { return .fail(io.err(bugPrompt())) }
                    return .from(bool: windowToFocus.focusWindow())
                } else {
                    return hitWorkspaceBoundaries(target, io, args, direction)
                }
            case .windowId(let windowId):
                if let windowToFocus = Window.get(byId: windowId) {
                    return .from(bool: windowToFocus.focusWindow())
                } else {
                    return .fail(io.err("Can't find window with ID \(windowId)"))
                }
            case .dfsIndex(let dfsIndex):
                if let windowToFocus = target.workspace.rootTilingContainer.allLeafWindowsRecursive.getOrNil(atIndex: Int(dfsIndex)) {
                    return .from(bool: windowToFocus.focusWindow())
                } else {
                    return .fail(io.err("Can't find window with DFS index \(dfsIndex)"))
                }
            case .dfsRelative(let nextPrev):
                let windows = target.workspace.rootTilingContainer.allLeafWindowsRecursive
                guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
                guard let currentIndex = windows.firstIndex(of: window) else {
                    return .fail(io.err("The window isn't part of the workspace tree")) // E.g. a floating window with --ignore-floating
                }
                var targetIndex = currentIndex + nextPrev.indexOffset
                if !(0 ..< windows.count).contains(targetIndex) {
                    switch args.boundariesAction {
                        case .stop: return .succ
                        case .fail: return .fail
                        case .wrapAroundTheWorkspace: targetIndex = (targetIndex + windows.count) % windows.count
                        case .wrapAroundAllMonitors: return .fail(io.err(bugPrompt("Must be discarded by args parser")))
                    }
                }
                return .from(bool: windows[targetIndex].focusWindow())
        }
    }
}

@MainActor private func hitWorkspaceBoundaries(
    _ target: LiveFocus,
    _ io: CmdIo,
    _ args: FocusCmdArgs,
    _ direction: CardinalDirection,
) -> BinaryExitCode {
    switch args.boundaries {
        case .workspace:
            return switch args.boundariesAction {
                case .stop: .succ
                case .fail: .fail
                case .wrapAroundTheWorkspace: wrapAroundTheWorkspace(target, io, direction)
                case .wrapAroundAllMonitors: .fail(io.err(bugPrompt("Must be discarded by args parser")))
            }
        case .allMonitorsOuterFrame:
            let currentMonitor = target.workspace.workspaceMonitor
            guard let (monitors, index) = currentMonitor.findRelativeMonitor(inDirection: direction) else {
                // No screens (e.g., during display reconfiguration): the monitor of the workspace is the fake mainMonitorInfo
                if !hasScreens { return .fail(io.err("Can't focus across monitors while there are no screens")) }
                return .fail(io.err(bugPrompt("Should never happen. Can't find the current monitor")))
            }

            if let targetMonitor = monitors.getOrNil(atIndex: index) {
                return .from(bool: targetMonitor.activeWorkspace.focusWorkspace())
            } else {
                guard let wrapped = monitors.get(wrappingIndex: index) else { return .fail(io.err(bugPrompt("\(index) \(monitors)"))) }
                return hitAllMonitorsOuterFrameBoundaries(target, io, args, direction, wrapped)
            }
    }
}

@MainActor private func hitAllMonitorsOuterFrameBoundaries(
    _ target: LiveFocus,
    _ io: CmdIo,
    _ args: FocusCmdArgs,
    _ direction: CardinalDirection,
    _ wrappedMonitor: MonitorInfo,
) -> BinaryExitCode {
    switch args.boundariesAction {
        case .stop:
            return .succ
        case .fail:
            return .fail
        case .wrapAroundTheWorkspace:
            return wrapAroundTheWorkspace(target, io, direction)
        case .wrapAroundAllMonitors:
            wrappedMonitor.activeWorkspace.findLeafWindowRecursive(snappedTo: direction.opposite)?.markAsMostRecentChild()
            return .from(bool: wrappedMonitor.activeWorkspace.focusWorkspace())
    }
}

@MainActor private func wrapAroundTheWorkspace(_ target: LiveFocus, _ io: CmdIo, _ direction: CardinalDirection) -> BinaryExitCode {
    guard let windowToFocus = target.workspace.findLeafWindowRecursive(snappedTo: direction.opposite) else {
        return .fail(io.err(noWindowIsFocused))
    }
    return .from(bool: windowToFocus.focusWindow())
}

@MainActor private func makeFloatingWindowsSeenAsTiling(workspace: Workspace) async -> [FloatingWindowData] {
    let mruBefore = workspace.mostRecentWindowRecursive
    defer {
        mruBefore?.markAsMostRecentChild()
    }
    var unsortedFloatingWindows: [FloatingWindowData] = []
    for window in workspace.floatingWindows {
        // todo bug: we shouldn't access ax api here. What if the window was moved but it wasn't committed to ax yet?
        guard let center = try? await window.getCenter(.nonCancellable) else { continue }

        let tilingParent: TilingContainer
        let index: Int
        if let target = center.coerce(in: workspace.workspaceMonitor.visibleRectPaddedByOuterGaps)?
            .findWindowRecursively(in: workspace.rootTilingContainer, virtual: true, fullscreenCoversAll: false)
        {
            guard let targetCenter = try? await target.getCenter(.nonCancellable) else { continue }
            guard let parent = target.parent as? TilingContainer else { continue }
            tilingParent = parent
            index = switch tilingParent.layout {
                case .tiles:
                    center.getProjection(tilingParent.orientation) >= targetCenter.getProjection(tilingParent.orientation)
                        ? target.ownIndex.orDie() + 1
                        : target.ownIndex.orDie()
                case .accordion:
                    center.getProjection(tilingParent.orientation) >= targetCenter.getProjection(tilingParent.orientation)
                        ? tilingParent.children.count
                        : 0
            }
        } else {
            index = 0
            tilingParent = workspace.rootTilingContainer
        }

        let data = window.unbindFromParent()
        let floatingWindowData = FloatingWindowData(
            window: window,
            center: center,
            tilingParent: tilingParent,
            adaptiveWeight: data.adaptiveWeight,
            index: index,
        )
        unsortedFloatingWindows.append(floatingWindowData)
    }
    let floatingWindows: [FloatingWindowData] = unsortedFloatingWindows.sortedBy { $0.center.getProjection($0.tilingParent.orientation) }.reversed()

    for floating in floatingWindows { // Make floating windows be seen as tiling
        floating.window.bind(to: floating.tilingParent, adaptiveWeight: 1, index: floating.index)
    }
    return floatingWindows
}

@MainActor private func restoreFloatingWindows(floatingWindows: [FloatingWindowData], workspace: Workspace) {
    let mruBefore = workspace.mostRecentWindowRecursive
    defer {
        mruBefore?.markAsMostRecentChild()
    }
    for floating in floatingWindows {
        floating.window.bind(to: workspace.floatingWindowsContainer, adaptiveWeight: floating.adaptiveWeight, index: INDEX_BIND_LAST)
    }
}

private struct FloatingWindowData {
    let window: Window
    let center: CGPoint

    let tilingParent: TilingContainer
    let adaptiveWeight: CGFloat
    let index: Int
}

extension TreeNode {
    func findLeafWindowRecursive(snappedTo direction: CardinalDirection) -> Window? {
        switch nodeCases {
            case .workspace(let workspace):
                return workspace.rootTilingContainer.findLeafWindowRecursive(snappedTo: direction)
            case .window(let window):
                return window
            case .tilingContainer(let container):
                if direction.orientation == container.orientation {
                    return (direction.isPositive ? container.children.last : container.children.first)?
                        .findLeafWindowRecursive(snappedTo: direction)
                } else {
                    return mostRecentChild?.findLeafWindowRecursive(snappedTo: direction)
                }
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer,
                 .floatingWindowsContainer:
                die("Impossible")
        }
    }
}
