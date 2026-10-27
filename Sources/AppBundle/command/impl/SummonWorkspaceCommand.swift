import AppKit
import Common

struct SummonWorkspaceCommand: Command {
    let args: SummonWorkspaceCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        // No screens (e.g., during display reconfiguration): the monitor of the focused workspace is the fake
        // mainMonitorInfo, so the workspace would be moved to the main monitor (and setFocus doesn't guard this path)
        if !hasScreens { return .fail(io.err("Can't summon workspace '\(args.target.val.raw)' while there are no screens")) }
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
