import AppKit
import Common

struct MoveCommand: Command {
    let args: MoveCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        let direction = args.direction.val
        guard let currentWindow = args.resolveWindowOrReportError(env, io) else { return .fail }
        if await shouldFailBecauseFullscreen_nonCancellable(
            window: currentWindow,
            failIfFullscreen: args.failIfFullscreen,
            failIfMacosNativeFullscreen: args.failIfMacosNativeFullscreen,
        ) {
            return .fail
        }
        switch currentWindow.parent?.cases {
            case nil: return .fail
            case .tilingContainer(let parent):
                guard let indexOfCurrent = currentWindow.ownIndex else { return .fail(io.err(bugPrompt())) }
                let indexOfSiblingTarget = indexOfCurrent + direction.focusOffset
                if parent.orientation == direction.orientation && parent.children.indices.contains(indexOfSiblingTarget) {
                    switch parent.children[indexOfSiblingTarget].tilingTreeNodeCasesOrDie() {
                        case .tilingContainer(let topLevelSiblingTargetContainer):
                            return deepMoveIn(window: currentWindow, into: topLevelSiblingTargetContainer, moveDirection: direction, io)
                        case .window: // "swap windows"
                            let prevBinding = currentWindow.unbindFromParent()
                            currentWindow.bind(to: parent, adaptiveWeight: prevBinding.adaptiveWeight, index: indexOfSiblingTarget)
                            return .succ
                    }
                } else {
                    return moveOut(tilingWindow: currentWindow, direction: direction, io, args, env)
                }
            case .floatingWindowsContainer: // floating window
                return .fail(io.err("moving floating windows isn't yet supported")) // todo
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer:
                return .fail(io.err(moveOutMacosUnconventionalWindow))
            case .macosPopupWindowsContainer, .workspace:
                return .fail(io.err(bugPrompt())) // Impossible
        }
    }
}

@MainActor private func hitWorkspaceBoundaries(
    _ window: Window,
    _ workspace: Workspace,
    _ io: CmdIo,
    _ args: MoveCmdArgs,
    _ direction: CardinalDirection,
    _ env: CmdEnv,
) -> BinaryExitCode {
    if args.boundaries == .allMonitorsOuterFrame {
        guard let (monitors, index) = window.nodeMonitor?.findRelativeMonitor(inDirection: direction) else {
            return .fail(io.err("Should never happen. Can't find the current monitor"))
        }
        if monitors.indices.contains(index) {
            let moveNodeToMonitorArgs = MoveNodeToMonitorCmdArgs(target: .direction(direction))
                .copy(\.windowId, window.windowId)
                .copy(\.focusFollowsWindow, focus.windowOrNil == window)

            return MoveNodeToMonitorCommand(args: moveNodeToMonitorArgs).run(env, io)
        }
    }
    switch args.boundariesAction {
        case .stop: return .succ
        case .fail: return .fail
        case .createImplicitContainer:
            let prevRoot = workspace.rootTilingContainer
            prevRoot.unbindFromParent()
            // Force tiles layout
            _ = TilingContainer(parent: workspace, adaptiveWeight: WEIGHT_AUTO, direction.orientation, .tiles, index: 0)
            check(prevRoot != workspace.rootTilingContainer)
            prevRoot.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: 0)
            window.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: direction.insertionOffset)
            return .succ
    }
}

private let moveOutMacosUnconventionalWindow = "moving macOS fullscreen, minimized windows and windows of hidden apps isn't yet supported. This behavior is subject to change"

@MainActor private func moveOut(
    tilingWindow window: Window,
    direction: CardinalDirection,
    _ io: CmdIo,
    _ args: MoveCmdArgs,
    _ env: CmdEnv,
) -> BinaryExitCode {
    let innerMostTilingContainer = window.parents.first(where: {
        // Stop searching if the parent isn't a tiling container: we have hit the workspace
        // (a tiling container's parent can only be a workspace or a tiling container)
        guard let parent = $0.parent as? TilingContainer else { return true }
        return parent.orientation == direction.orientation
    }) as? TilingContainer
    guard let innerMostTilingContainer else { return .fail(io.err(bugPrompt())) } // Impossible
    switch innerMostTilingContainer.parent?.cases {
        case nil: return .fail
        case .tilingContainer(let parent):
            check(parent.orientation == direction.orientation)
            guard let ownIndex = innerMostTilingContainer.ownIndex else { return .fail(io.err(bugPrompt())) }
            window.bind(to: parent, adaptiveWeight: WEIGHT_AUTO, index: ownIndex + direction.insertionOffset)
            return .succ
        case .workspace(let parent):
            return hitWorkspaceBoundaries(window, parent, io, args, direction, env)
        case .floatingWindowsContainer, .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
             .macosHiddenAppsWindowsContainer, .macosPopupWindowsContainer:
            illegalChildParentRelation(child: innerMostTilingContainer, parent: nil)
    }
}

@MainActor private func deepMoveIn(window: Window, into container: TilingContainer, moveDirection: CardinalDirection, _ io: CmdIo) -> BinaryExitCode {
    // Descend through the most recent children to a container with the move orientation or to a window
    var deepTarget: TreeNode = container
    while let tilingContainer = deepTarget as? TilingContainer, tilingContainer.orientation != moveDirection.orientation {
        deepTarget = tilingContainer.mostRecentChild.orDie("Empty containers must be detached during normalization")
    }
    if let deepTarget = deepTarget as? TilingContainer {
        window.bind(to: deepTarget, adaptiveWeight: WEIGHT_AUTO, index: 0)
    } else {
        guard let parent = deepTarget.parent as? TilingContainer else { return .fail(io.err(bugPrompt())) }
        guard let deepTargetIndex = deepTarget.ownIndex else { return .fail(io.err(bugPrompt())) }
        window.bind(to: parent, adaptiveWeight: WEIGHT_AUTO, index: deepTargetIndex + 1)
    }
    return .succ
}

@MainActor func shouldFailBecauseFullscreen_nonCancellable(
    window: Window,
    failIfFullscreen: Bool,
    failIfMacosNativeFullscreen: Bool,
) async -> Bool {
    if failIfFullscreen && window.isFullscreen { return true }
    guard failIfMacosNativeFullscreen else { return false }
    return true == (try? await window.isMacosFullscreen(.nonCancellable))
}
