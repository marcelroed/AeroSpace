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
                guard let currentIndex = windows.firstIndex(where: { $0 == target.windowOrNil }) else {
                    return .fail
                }
                let targetIndex = currentIndex + nextPrev.indexOffset
                if let windowToFocus = windows.getOrNil(atIndex: targetIndex) {
                    return .from(bool: windowToFocus.focusWindow())
                }
                switch args.boundariesAction {
                    case .stop: return .succ
                    case .fail: return .fail
                    case .wrapAroundTheWorkspace: return .from(bool: windows.get(wrappingIndex: targetIndex).orDie().focusWindow())
                    case .wrapAroundAllMonitors: return .fail(io.err(bugPrompt("Must be discarded by args parser")))
                }
        }
    }
}

@MainActor private func hitWorkspaceBoundaries(
    _ target: LiveFocus,
    _ io: CmdIo,
    _ args: FocusCmdArgs,
    _ direction: CardinalDirection,
) -> BinaryExitCode {
    var wrappedMonitor: MonitorInfo? = nil
    if args.boundaries == .allMonitorsOuterFrame {
        guard let (monitors, index) = target.workspace.workspaceMonitor.findRelativeMonitor(inDirection: direction) else {
            return .fail(io.err(bugPrompt("Should never happen. Can't find the current monitor")))
        }
        if let targetMonitor = monitors.getOrNil(atIndex: index) {
            return .from(bool: targetMonitor.activeWorkspace.focusWorkspace())
        }
        guard let wrapped = monitors.get(wrappingIndex: index) else { return .fail(io.err(bugPrompt("\(index) \(monitors)"))) }
        wrappedMonitor = wrapped
    }
    switch args.boundariesAction {
        case .stop: return .succ
        case .fail: return .fail
        case .wrapAroundTheWorkspace:
            guard let windowToFocus = target.workspace.findLeafWindowRecursive(snappedTo: direction.opposite) else {
                return .fail(io.err(noWindowIsFocused))
            }
            return .from(bool: windowToFocus.focusWindow())
        case .wrapAroundAllMonitors:
            guard let wrappedMonitor else { return .fail(io.err("Must be discarded by args parser")) }
            wrappedMonitor.activeWorkspace.findLeafWindowRecursive(snappedTo: direction.opposite)?.markAsMostRecentChild()
            return .from(bool: wrappedMonitor.activeWorkspace.focusWorkspace())
    }
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
