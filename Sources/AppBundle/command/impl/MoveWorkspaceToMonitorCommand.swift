import AppKit
import Common

struct MoveWorkspaceToMonitorCommand: Command {
    let args: MoveWorkspaceToMonitorCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        let focusedWorkspace = target.workspace
        let prevMonitor = focusedWorkspace.workspaceMonitor

        guard let targetMonitor = args.target.val.resolve(target.workspace.workspaceMonitor, wrapAround: args.wrapAround)
            .getOrNil(appendErrorTo: &io.stderr) else { return .fail }
        if targetMonitor.monitorId_oneBased == prevMonitor.monitorId_oneBased {
            return .succ
        }
        return .from(bool: moveWorkspace(focusedWorkspace, to: targetMonitor, stubbing: prevMonitor, io))
    }
}

/// Shows `workspace` on `monitor` and a stub workspace on `prevMonitor`. Returns false with an error if force assignment forbids it
@MainActor
func moveWorkspace(_ workspace: Workspace, to monitor: MonitorInfo, stubbing prevMonitor: MonitorInfo?, _ io: CmdIo) -> Bool {
    guard monitor.setActiveWorkspace(workspace) else {
        io.err("Can't move workspace '\(workspace.name)' to monitor '\(monitor.name)'. workspace-to-monitor-force-assignment doesn't allow it")
        return false
    }
    if let prevMonitor {
        let stubWorkspace = getStubWorkspace(for: prevMonitor)
        check(
            prevMonitor.setActiveWorkspace(stubWorkspace),
            "getStubWorkspace generated incompatible stub workspace (\(stubWorkspace)) for the monitor (\(prevMonitor)",
        )
    }
    return true
}
