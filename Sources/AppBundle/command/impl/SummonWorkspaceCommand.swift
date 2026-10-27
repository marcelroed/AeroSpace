import AppKit
import Common

struct SummonWorkspaceCommand: nonisolated Command {
    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var target: WorkspaceName
    var failIfNoop = false

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var failIfNoop = false
        while let option = try a.nextOption() {
            switch option {
                case "--fail-if-noop": failIfNoop = true
                default: throw .unknownOption(option)
            }
        }
        let target = try parseWorkspaceName(a.positional("<workspace>"))
        try a.end()
        return Self(target: target, failIfNoop: failIfNoop)
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        // No screens (e.g., during display reconfiguration): the monitor of the focused workspace is the fake
        // mainMonitorInfo, so the workspace would be moved to the main monitor (and setFocus doesn't guard this path)
        if !hasScreens { throw "Can't summon workspace '\(target.raw)' while there are no screens" }
        let workspace = Workspace.get(byName: target.raw)
        let monitor = focus.workspace.workspaceMonitor
        if monitor.activeWorkspace == workspace {
            return try noop(cx, failIfNoop: failIfNoop, "Workspace '\(workspace.name)' is already visible on the focused monitor. Tip: use --fail-if-noop to exit with non-zero code")
        }
        let prevMonitor = workspace.isVisible ? workspace.workspaceMonitor : nil
        try moveWorkspace(workspace, to: monitor, stubbing: prevMonitor)
        if !workspace.focusWorkspace() { throw .silent }
    }
}
