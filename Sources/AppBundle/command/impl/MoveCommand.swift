import AppKit
import Common

struct MoveCommand: nonisolated Command {
    nonisolated enum WhenBoundariesCrossed: String, CaseIterable, Equatable, Sendable {
        case stop = "stop"
        case fail = "fail"
        case createImplicitContainer = "create-implicit-container"
    }

    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var direction: CardinalDirection
    var boundaries: Boundaries = .workspace
    var boundariesAction: WhenBoundariesCrossed = .createImplicitContainer
    var failIfFullscreen = false
    var failIfMacosNativeFullscreen = false
    var windowId: UInt32? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var boundaries: Boundaries = .workspace
        var boundariesAction: WhenBoundariesCrossed = .createImplicitContainer
        var failIfFullscreen = false
        var failIfMacosNativeFullscreen = false
        var windowId: UInt32? = nil
        while let option = try a.nextOption() {
            switch option {
                case "--window-id": windowId = try a.windowId(of: option)
                case "--boundaries": boundaries = try a.value(of: option, "<boundary>")
                case "--boundaries-action": boundariesAction = try a.value(of: option, "<action>")
                case "--fail-if-fullscreen": failIfFullscreen = true
                case "--fail-if-macos-native-fullscreen": failIfMacosNativeFullscreen = true
                default: throw .unknownOption(option)
            }
        }
        let direction: CardinalDirection = try a.positional()
        try a.end()
        return Self(
            direction: direction,
            boundaries: boundaries,
            boundariesAction: boundariesAction,
            failIfFullscreen: failIfFullscreen,
            failIfMacosNativeFullscreen: failIfMacosNativeFullscreen,
            windowId: windowId,
        )
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let currentWindow = try cx.window(windowId: windowId)
        if await shouldFailBecauseFullscreen_nonCancellable(
            window: currentWindow,
            failIfFullscreen: failIfFullscreen,
            failIfMacosNativeFullscreen: failIfMacosNativeFullscreen,
        ) {
            throw .silent
        }
        switch currentWindow.placement {
            case nil: throw .silent
            case .tiling(let parent):
                guard let indexOfCurrent = currentWindow.ownIndex else { throw CmdFail(bugPrompt()) }
                let indexOfSiblingTarget = indexOfCurrent + direction.focusOffset
                if parent.orientation == direction.orientation && parent.children.indices.contains(indexOfSiblingTarget) {
                    switch parent.children[indexOfSiblingTarget] {
                        case let topLevelSiblingTargetContainer as TilingContainer:
                            try deepMoveIn(window: currentWindow, into: topLevelSiblingTargetContainer)
                        default: // A window: "swap windows"
                            let prevBinding = currentWindow.unbindFromParent()
                            currentWindow.bind(to: parent, weight: prevBinding.weight, index: indexOfSiblingTarget)
                    }
                } else {
                    try await moveOut(tilingWindow: currentWindow, cx)
                }
            case .floating: // floating window
                throw "moving floating windows isn't yet supported" // todo
            case .macosMinimized, .macosFullscreen, .macosHiddenApp:
                throw CmdFail(moveOutMacosUnconventionalWindow)
            case .macosPopup:
                throw CmdFail(bugPrompt()) // Impossible
        }
    }

    private func hitWorkspaceBoundaries(_ window: Window, _ workspace: Workspace, _ cx: CmdContext) async throws(CmdFail) {
        switch boundaries {
            case .workspace: break
            case .allMonitorsOuterFrame:
                guard let (monitors, index) = window.nodeMonitor?.findRelativeMonitor(inDirection: direction) else {
                    // No screens (e.g., during display reconfiguration): the monitor of the window is the fake mainMonitorInfo
                    if !hasScreens { throw "Can't move the window across monitors while there are no screens" }
                    throw CmdFail(bugPrompt("Should never happen. Can't find the current monitor"))
                }
                if monitors.indices.contains(index) {
                    let moveNodeToMonitor = MoveNodeToMonitorCommand(
                        target: .direction(direction),
                        focusFollowsWindow: focus.windowOrNil == window,
                        windowId: window.windowId,
                    )
                    return try await moveNodeToMonitor.run(cx)
                }
        }
        switch boundariesAction {
            case .stop: return
            case .fail: throw .silent
            case .createImplicitContainer:
                let prevRoot = workspace.rootTilingContainer
                prevRoot.unbindFromParent()
                // Force tiles layout
                _ = TilingContainer(parent: workspace, direction.orientation, .tiles, index: 0)
                check(prevRoot != workspace.rootTilingContainer)
                prevRoot.bind(to: workspace.rootTilingContainer, index: 0)
                window.bind(to: workspace.rootTilingContainer, index: direction.insertionOffset)
        }
    }

    private func moveOut(tilingWindow window: Window, _ cx: CmdContext) async throws(CmdFail) {
        let innerMostTilingContainer = window.parents.first(where: {
            // Stop searching if the parent isn't a tiling container: we have hit the workspace
            // (a tiling container's parent can only be a workspace or a tiling container)
            guard let parent = $0.parent as? TilingContainer else { return true }
            return parent.orientation == direction.orientation
        }) as? TilingContainer
        guard let innerMostTilingContainer else { throw CmdFail(bugPrompt()) } // Impossible
        switch innerMostTilingContainer.parent {
            case nil: throw .silent
            case let parent as TilingContainer:
                check(parent.orientation == direction.orientation)
                guard let ownIndex = innerMostTilingContainer.ownIndex else { throw CmdFail(bugPrompt()) }
                window.bind(to: parent, index: ownIndex + direction.insertionOffset)
            case let parent as Workspace:
                try await hitWorkspaceBoundaries(window, parent, cx)
            default:
                die("A tiling container's parent is a tiling container or a workspace")
        }
    }

    private func deepMoveIn(window: Window, into container: TilingContainer) throws(CmdFail) {
        // Descend through the most recent children to a container with the move orientation or to a window
        var deepTarget: TreeNode = container
        while let tilingContainer = deepTarget as? TilingContainer, tilingContainer.orientation != direction.orientation {
            deepTarget = tilingContainer.mostRecentChild.orDie("Empty containers must be detached during normalization")
        }
        if let deepTarget = deepTarget as? TilingContainer {
            window.bind(to: deepTarget, index: 0)
        } else {
            guard let parent = deepTarget.parent as? TilingContainer else { throw CmdFail(bugPrompt()) }
            guard let deepTargetIndex = deepTarget.ownIndex else { throw CmdFail(bugPrompt()) }
            window.bind(to: parent, index: deepTargetIndex + 1)
        }
    }
}

private let moveOutMacosUnconventionalWindow = "moving macOS fullscreen, minimized windows and windows of hidden apps isn't yet supported. This behavior is subject to change"

func shouldFailBecauseFullscreen_nonCancellable(
    window: Window,
    failIfFullscreen: Bool,
    failIfMacosNativeFullscreen: Bool,
) async -> Bool {
    if failIfFullscreen && window.isFullscreen { return true }
    guard failIfMacosNativeFullscreen else { return false }
    return true == (try? await window.isMacosFullscreen(.nonCancellable))
}
