import AppKit
import Common

struct MoveNodeToWorkspaceCommand: nonisolated Command {
    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var target: WorkspaceTarget
    var wrapAround = false
    var failIfNoop = false
    var focusFollowsWindow = false
    var useStdin = false
    var windowId: UInt32? = nil

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
        let target = try WorkspaceTarget.parse(&a)
        try a.end()
        let relative = target.isRelative
        if wrapAround && !relative { throw "--wrap-around requires using \(NextPrev.unionLiteral) argument" }
        if failIfNoop && relative { throw "--fail-if-noop is incompatible with \(NextPrev.unionLiteral)" }
        if windowId != nil && relative { throw "--window-id is incompatible with \(NextPrev.unionLiteral)" }
        if useStdin && !relative { throw "--stdin requires using \(NextPrev.unionLiteral) argument" }
        return Self(
            target: target,
            wrapAround: wrapAround,
            failIfNoop: failIfNoop,
            focusFollowsWindow: focusFollowsWindow,
            useStdin: useStdin,
            windowId: windowId,
        )
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let target = try cx.target(windowId: windowId)
        guard let window = target.windowOrNil else { throw CmdFail(noWindowIsFocused) }
        let targetWorkspace: Workspace = switch self.target {
            case .relative(let nextPrev):
                try getNextPrevWorkspace(
                    current: target.workspace, // == window.nodeWorkspace
                    isNext: nextPrev == .next,
                    wrapAround: wrapAround,
                    stdin: useStdin ? cx.readStdin() : nil,
                )
            case .direct(let name):
                Workspace.get(byName: name.raw)
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
