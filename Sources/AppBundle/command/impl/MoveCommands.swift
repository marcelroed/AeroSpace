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
    var windowId: WindowId? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var boundaries: Boundaries = .workspace
        var boundariesAction: WhenBoundariesCrossed = .createImplicitContainer
        var failIfFullscreen = false
        var failIfMacosNativeFullscreen = false
        var windowId: WindowId? = nil
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
        let window = try cx.window(windowId: windowId)
        try await window.failIfFullscreen(failIfFullscreen, macosNativeFullscreen: failIfMacosNativeFullscreen)
        // The window may have closed or moved at the suspension point above
        guard let (workspace, placement) = window.workspacePlacement else { throw .silent }
        switch placement {
            case .tiling(let parent):
                let siblingIndex = parent.children.firstIndex(of: window).orDie() + direction.focusOffset
                let sibling = parent.orientation == direction.orientation ? parent.children.getOrNil(atIndex: siblingIndex) : nil
                if let container = sibling as? TilingContainer {
                    moveIn(window, container)
                } else if sibling != nil {
                    window.move(to: parent, at: siblingIndex, weight: .keep) // The window and the sibling window trade places
                } else {
                    try await moveOut(window, workspace, cx)
                }
            case .floating: // floating window
                throw "moving floating windows isn't yet supported" // todo
            case .macosFullscreen, .macosHiddenApp:
                throw CmdFail(moveOutMacosUnconventionalWindow)
        }
    }

    /// Moves the window into `container`: the way follows the most recent children down to a container with the move's
    /// orientation (the window becomes its first child) or to a window (the window goes after it)
    private func moveIn(_ window: Window, _ container: TilingContainer) {
        var target: TreeNode = container
        while let it = target as? TilingContainer, it.orientation != direction.orientation {
            target = it.mostRecentChild.orDie("Empty containers must be detached during normalization")
        }
        if let target = target as? TilingContainer {
            window.move(to: target, at: 0)
        } else {
            let (parent, index) = target.tilingSlot.orDie()
            window.move(to: parent, at: index + 1)
        }
    }

    /// Moves the window next to its innermost ancestor whose parent has the move's orientation
    private func moveOut(_ window: Window, _ workspace: Workspace, _ cx: CmdContext) async throws(CmdFail) {
        if let (_, parent, index) = window.tilingPath.dropFirst().first(where: { $0.parent.orientation == direction.orientation }) {
            window.move(to: parent, at: index + direction.insertionOffset)
        } else {
            try await atWorkspaceEdge(window, workspace, cx)
        }
    }

    private func atWorkspaceEdge(_ window: Window, _ workspace: Workspace, _ cx: CmdContext) async throws(CmdFail) {
        if boundaries == .allMonitorsOuterFrame, try !workspace.workspaceMonitor.monitor(in: direction).wrapped {
            let moveNodeToMonitor = MoveNodeToMonitorCommand(
                target: .direction(direction),
                focusFollowsWindow: focus.windowOrNil == window,
                windowId: window.windowId,
            )
            return try await delegate(to: moveNodeToMonitor, cx)
        }
        switch boundariesAction {
            case .stop: return
            case .fail: throw .silent
            case .createImplicitContainer:
                let root = workspace.rootTilingContainerCreatingIfNeeded().wrap(direction.orientation, .tiles) // Force tiles layout
                window.move(to: root, at: direction.insertionOffset)
        }
    }
}

private let moveOutMacosUnconventionalWindow = "moving macOS fullscreen, minimized windows and windows of hidden apps isn't yet supported. This behavior is subject to change"

extension Window {
    /// `--fail-if-fullscreen` and `--fail-if-macos-native-fullscreen`: fail silently if the window is fullscreen
    func failIfFullscreen(_ fullscreen: Bool, macosNativeFullscreen: Bool) async throws(CmdFail) {
        if fullscreen && isFullscreen { throw .silent }
        if !macosNativeFullscreen { return }
        let isMacosFullscreen = switch await world.platform.facts(windowId) {
            case .facts(let facts): facts.isFullscreen
            // A busy app: what the last refresh saw, not false: focus and move would go on around a fullscreen window
            case .noAnswer: if case .macosFullscreen = placement { true } else { false }
            case .closed: false
        }
        if isMacosFullscreen { throw .silent }
    }
}

struct SwapCommand: nonisolated Command {
    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var target: CardinalOrDfsDirection
    var swapFocus = false
    var wrapAround = false
    var windowId: WindowId? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var swapFocus = false
        var wrapAround = false
        var windowId: WindowId? = nil
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
        guard let window = liveFocus.windowOrNil else { throw CmdFail(noWindowIsFocused) }
        guard case .tiling = window.placement else { throw "Can't swap a window that isn't tiled" } // RB-108
        let targetWindow: Window?
        switch target {
            case .direction(let direction):
                // With --wrap-around, the workspace is the neighbor beyond its edge: the window at its other end
                let neighbor: TreeNode? = window.neighbor(direction) ?? (wrapAround ? liveFocus.workspace : nil)
                targetWindow = neighbor?.edgeWindow(snappedTo: direction.opposite)
            case .dfsRelative(let nextPrev):
                targetWindow = try liveFocus.workspace.dfsNeighbor(of: window, nextPrev, wrapAround: wrapAround)
        }
        guard let targetWindow else { throw .silent }
        window.swap(with: targetWindow)
        if swapFocus && !targetWindow.focusWindow() { throw .silent }
    }
}

struct JoinWithCommand: nonisolated Command {
    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var direction: CardinalDirection
    var windowId: WindowId? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var windowId: WindowId? = nil
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
        let window = try cx.window(windowId: windowId)
        guard let (parent, index) = window.closestParent(hasChildrenIn: direction) else {
            throw CmdFail("No windows in the specified direction")
        }
        let container = parent.children[index + direction.focusOffset].wrap(parent.orientation.opposite, .tiles)
        window.move(to: container, at: direction.isPositive ? 0 : nil)
    }
}

struct MoveNodeToWorkspaceCommand: nonisolated Command {
    /// Each target carries the options that apply to it
    nonisolated enum Target: Equatable, Sendable {
        case relative(NextPrev, wrapAround: Bool = false, useStdin: Bool = false)
        case direct(WorkspaceName, failIfNoop: Bool = false, windowId: WindowId? = nil)
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
        var windowId: WindowId? = nil
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
        let windowId: WindowId? = if case .direct(_, _, let windowId) = self.target { windowId } else { nil }
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
        ? targetWorkspace.containerCreatingIfNeeded(.floating)
        : targetWorkspace.rootTilingContainerCreatingIfNeeded()
    window.move(to: targetContainer, at: index)
    // On a workspace, focusing the window fails only while there are no screens, if the workspace isn't visible
    if focusFollowsWindow && !window.focusWindow() {
        throw "Can't follow the window to workspace '\(targetWorkspace.name)' while there are no screens"
    }
}

struct MoveNodeToMonitorCommand: nonisolated Command {
    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var target: MonitorTarget
    var wrapAround = false
    var focusFollowsWindow = false
    var failIfNoop = false
    var windowId: WindowId? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var wrapAround = false
        var focusFollowsWindow = false
        var failIfNoop = false
        var windowId: WindowId? = nil
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
            .map { dir in dir.isPositive && targetWs.rootLayout.orientation == dir.orientation }
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
        try moveWorkspace(focusedWorkspace, to: targetMonitor)
    }
}

/// Shows `workspace` on `monitor`. The monitor that it leaves gets a stub workspace. Fails if force assignment forbids it
func moveWorkspace(_ workspace: Workspace, to monitor: MonitorInfo) throws(CmdFail) {
    guard monitor.setActiveWorkspace(workspace) else {
        throw "Can't move workspace '\(workspace.name)' to monitor '\(monitor.name)'. workspace-to-monitor-force-assignment doesn't allow it"
    }
}
