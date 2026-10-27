import AppKit
import Common

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
