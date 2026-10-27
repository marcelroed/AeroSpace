import AppKit
import Common

struct SummonWorkspaceCommand: Command {
    let args: SummonWorkspaceCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        let workspace = Workspace.get(byName: args.target.val.raw)
        let monitor = focus.workspace.workspaceMonitor
        if monitor.activeWorkspace == workspace {
            return .noop(io, failIfNoop: args.failIfNoop, "Workspace '\(workspace.name)' is already visible on the focused monitor. Tip: use --fail-if-noop to exit with non-zero code")
        }
        let prevMonitor = workspace.isVisible ? workspace.workspaceMonitor : nil
        guard moveWorkspace(workspace, to: monitor, stubbing: prevMonitor, io) else { return .fail }
        return .from(bool: workspace.focusWorkspace())
    }
}
