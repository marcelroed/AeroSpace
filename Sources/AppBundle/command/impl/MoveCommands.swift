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
                    return try await delegate(to: moveNodeToMonitor, cx)
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

struct SwapCommand: nonisolated Command {
    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var target: CardinalOrDfsDirection
    var swapFocus = false
    var wrapAround = false
    var windowId: UInt32? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var swapFocus = false
        var wrapAround = false
        var windowId: UInt32? = nil
        while let option = try a.nextOption() {
            switch option {
                case "--swap-focus": swapFocus = true
                case "--wrap-around": wrapAround = true
                case "--window-id": windowId = try a.windowId(of: option)
                default: throw .unknownOption(option)
            }
        }
        let target: CardinalOrDfsDirection = try a.positional()
        try a.end()
        return Self(target: target, swapFocus: swapFocus, wrapAround: wrapAround, windowId: windowId)
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let liveFocus = try cx.target(windowId: windowId)
        guard let currentWindow = liveFocus.windowOrNil else { throw CmdFail(noWindowIsFocused) }

        let targetWindow: Window?
        switch target {
            case .direction(let direction):
                switch currentWindow.closestParent(hasChildrenInDirection: direction, withLayout: nil) {
                    case let (parent, ownIndex)?:
                        targetWindow = parent.children[ownIndex + direction.focusOffset].findLeafWindowRecursive(snappedTo: direction.opposite)
                    case nil where wrapAround:
                        targetWindow = liveFocus.workspace.findLeafWindowRecursive(snappedTo: direction.opposite)
                    case nil:
                        throw .silent
                }
            case .dfsRelative(let nextPrev):
                let windows = liveFocus.workspace.rootTilingContainer.allLeafWindowsRecursive
                guard let currentIndex = windows.firstIndex(where: { $0 == liveFocus.windowOrNil }) else { throw .silent }
                let targetIndex = currentIndex + nextPrev.indexOffset
                targetWindow = wrapAround ? windows.get(wrappingIndex: targetIndex) : windows.getOrNil(atIndex: targetIndex)
        }

        guard let targetWindow else { throw .silent }

        swapWindows(mruDominant: currentWindow, targetWindow)

        if swapFocus && !targetWindow.focusWindow() { throw .silent }
    }
}

struct JoinWithCommand: nonisolated Command {
    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var direction: CardinalDirection
    var windowId: UInt32? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var windowId: UInt32? = nil
        while let option = try a.nextOption() {
            switch option {
                case "--window-id": windowId = try a.windowId(of: option)
                default: throw .unknownOption(option)
            }
        }
        let result = Self(direction: try a.positional(), windowId: windowId)
        try a.end()
        return result
    }

    func run(_ cx: CmdContext) throws(CmdFail) {
        let currentWindow = try cx.window(windowId: windowId)
        guard let (parent, ownIndex) = currentWindow.closestParent(hasChildrenInDirection: direction, withLayout: nil) else {
            throw CmdFail("No windows in the specified direction")
        }
        let joinWithTarget = parent.children[ownIndex + direction.focusOffset]
        let prevBinding = joinWithTarget.unbindFromParent()
        let newParent = TilingContainer(
            parent: parent,
            weight: prevBinding.weight,
            parent.orientation.opposite,
            .tiles,
            index: prevBinding.index,
        )
        currentWindow.unbindFromParent()

        joinWithTarget.bind(to: newParent, index: 0)
        currentWindow.bind(to: newParent, index: direction.isPositive ? 0 : nil)
    }
}

struct MoveNodeToWorkspaceCommand: nonisolated Command {
    /// Each target carries the options that apply to it
    nonisolated enum Target: Equatable, Sendable {
        case relative(NextPrev, wrapAround: Bool = false, useStdin: Bool = false)
        case direct(WorkspaceName, failIfNoop: Bool = false, windowId: UInt32? = nil)
    }

    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var target: Target
    var focusFollowsWindow = false

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var wrapAround = false
        var failIfNoop = false
        var focusFollowsWindow = false
        var useStdin = false
        var windowId: UInt32? = nil
        while let option = try a.nextOption() {
            switch option {
                case "--wrap-around": wrapAround = true
                case "--fail-if-noop": failIfNoop = true
                case "--focus-follows-window": focusFollowsWindow = true
                case "--stdin": useStdin = true
                case "--window-id": windowId = try a.windowId(of: option)
                default: throw .unknownOption(option)
            }
        }
        let arg = try WorkspaceArg.parse(&a)
        try a.end()
        let target: Target
        switch arg {
            case .relative(let nextPrev):
                if failIfNoop { throw "--fail-if-noop is incompatible with \(NextPrev.unionLiteral)" }
                if windowId != nil { throw "--window-id is incompatible with \(NextPrev.unionLiteral)" }
                target = .relative(nextPrev, wrapAround: wrapAround, useStdin: useStdin)
            case .direct(let name):
                if wrapAround { throw "--wrap-around requires using \(NextPrev.unionLiteral) argument" }
                if useStdin { throw "--stdin requires using \(NextPrev.unionLiteral) argument" }
                target = .direct(name, failIfNoop: failIfNoop, windowId: windowId)
        }
        return Self(target: target, focusFollowsWindow: focusFollowsWindow)
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let windowId: UInt32? = if case .direct(_, _, let windowId) = self.target { windowId } else { nil }
        let target = try cx.target(windowId: windowId)
        guard let window = target.windowOrNil else { throw CmdFail(noWindowIsFocused) }
        let targetWorkspace: Workspace
        let failIfNoop: Bool
        switch self.target {
            case .relative(let nextPrev, let wrapAround, let useStdin):
                targetWorkspace = try getNextPrevWorkspace(
                    current: target.workspace, // == window.nodeWorkspace
                    isNext: nextPrev == .next,
                    wrapAround: wrapAround,
                    stdin: useStdin ? cx.readStdin() : nil,
                )
                failIfNoop = false
            case .direct(let name, let failIfNoopOption, _):
                targetWorkspace = Workspace.get(byName: name.raw)
                failIfNoop = failIfNoopOption
        }
        try moveWindowToWorkspace(window, targetWorkspace, cx, focusFollowsWindow: focusFollowsWindow, failIfNoop: failIfNoop)
    }
}

func moveWindowToWorkspace(
    _ window: Window,
    _ targetWorkspace: Workspace,
    _ cx: CmdContext,
    focusFollowsWindow: Bool,
    failIfNoop: Bool,
    index: Int? = nil,
) throws(CmdFail) {
    if window.nodeWorkspace == targetWorkspace {
        return try noop(cx, failIfNoop: failIfNoop, "Window '\(window.windowId)' already belongs to workspace '\(targetWorkspace.name)'. Tip: use --fail-if-noop to exit with non-zero code")
    }
    let targetContainer: Container = window.isFloating
        ? targetWorkspace.floatingWindowsContainer
        : targetWorkspace.rootTilingContainer
    window.bind(to: targetContainer, index: index)
    if focusFollowsWindow && !window.focusWindow() { throw .silent }
}

struct MoveNodeToMonitorCommand: nonisolated Command {
    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var target: MonitorTarget
    var wrapAround = false
    var focusFollowsWindow = false
    var failIfNoop = false
    var windowId: UInt32? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var wrapAround = false
        var focusFollowsWindow = false
        var failIfNoop = false
        var windowId: UInt32? = nil
        while let option = try a.nextOption() {
            switch option {
                case "--wrap-around": wrapAround = true
                case "--focus-follows-window": focusFollowsWindow = true
                case "--fail-if-noop": failIfNoop = true
                case "--window-id": windowId = try a.windowId(of: option)
                default: throw .unknownOption(option)
            }
        }
        let target = try MonitorTarget.parse(&a)
        try a.end()
        if wrapAround && target.isPatterns { throw "--wrap-around is incompatible with <monitor-pattern> argument" }
        if failIfNoop && !target.isPatterns { throw "--fail-if-noop is incompatible with \(MonitorTarget.casesExceptPatterns.joinedCliArgs)" }
        return Self(target: target, wrapAround: wrapAround, focusFollowsWindow: focusFollowsWindow, failIfNoop: failIfNoop, windowId: windowId)
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let window = try cx.window(windowId: windowId)
        guard let currentMonitor = window.nodeMonitor else { throw CmdFail(windowIsntPartOfTree(window)) }
        let targetMonitor = try target.resolve(currentMonitor, wrapAround: wrapAround)
        let targetWs = targetMonitor.activeWorkspace
        let index = true == target.directionOrNil
            .map { dir in dir.isPositive && targetWs.rootTilingContainer.orientation == dir.orientation }
            ? 0
            : nil
        try moveWindowToWorkspace(window, targetWs, cx, focusFollowsWindow: focusFollowsWindow, failIfNoop: failIfNoop, index: index)
    }
}

func windowIsntPartOfTree(_ window: Window) -> String {
    "Window \(window.windowId) is not part of tree (minimized or hidden)"
}

struct MoveWorkspaceToMonitorCommand: nonisolated Command {
    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var target: MonitorTarget
    var wrapAround = false
    var workspace: WorkspaceName? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var wrapAround = false
        var workspace: WorkspaceName? = nil
        while let option = try a.nextOption() {
            switch option {
                case "--wrap-around": wrapAround = true
                case "--workspace": workspace = try a.workspace(of: option)
                default: throw .unknownOption(option)
            }
        }
        let target = try MonitorTarget.parse(&a)
        try a.end()
        if wrapAround && target.isPatterns { throw "--wrap-around is incompatible with <monitor-pattern> argument" }
        return Self(target: target, wrapAround: wrapAround, workspace: workspace)
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let focusedWorkspace = try cx.target(workspace: workspace).workspace
        let prevMonitor = focusedWorkspace.workspaceMonitor
        let targetMonitor = try target.resolve(prevMonitor, wrapAround: wrapAround)
        if targetMonitor.monitorId_oneBased == prevMonitor.monitorId_oneBased { return }
        try moveWorkspace(focusedWorkspace, to: targetMonitor, stubbing: prevMonitor)
    }
}

/// Shows `workspace` on `monitor` and a stub workspace on `prevMonitor`. Fails if force assignment forbids it
func moveWorkspace(_ workspace: Workspace, to monitor: MonitorInfo, stubbing prevMonitor: MonitorInfo?) throws(CmdFail) {
    guard monitor.setActiveWorkspace(workspace) else {
        throw "Can't move workspace '\(workspace.name)' to monitor '\(monitor.name)'. workspace-to-monitor-force-assignment doesn't allow it"
    }
    if let prevMonitor {
        let stubWorkspace = getStubWorkspace(for: prevMonitor)
        check(
            prevMonitor.setActiveWorkspace(stubWorkspace),
            "getStubWorkspace generated incompatible stub workspace (\(stubWorkspace.description)) for the monitor (\(prevMonitor))",
        )
    }
}
