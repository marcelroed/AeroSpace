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
        if monitor.setActiveWorkspace(workspace) {
            if let prevMonitor {
                let stubWorkspace = getStubWorkspace(for: prevMonitor)
                check(
                    prevMonitor.setActiveWorkspace(stubWorkspace),
                    "getStubWorkspace generated incompatible stub workspace (\(stubWorkspace.description)) for the monitor (\(prevMonitor))",
                )
            }
            return .from(bool: workspace.focusWorkspace())
        } else {
            return .fail(io.err("Can't move workspace '\(workspace.name)' to monitor '\(monitor.name)'. workspace-to-monitor-force-assignment doesn't allow it"))
        }
    }
}
