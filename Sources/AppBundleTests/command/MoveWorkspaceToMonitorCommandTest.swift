@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct MoveWorkspaceToMonitorCommandTest {
    @Test
    func parse() {
        expectEqual(parseMoveWorkspaceToMonitorTarget("move-workspace-to-monitor next"), .relative(.next))
        expectEqual(parseMoveWorkspaceToMonitorTarget("move-workspace-to-monitor main"), .patterns([.main]))
        expectEqual(parseMoveWorkspaceToMonitorTarget("move-workspace-to-monitor -- next"), .patterns([.pattern("next")]))
    }

    @Test(arguments: [
        ("move-workspace-to-monitor --", "Argument '(left|down|up|right|next|prev|<monitor-pattern>)' is mandatory"),
        ("move-workspace-to-monitor --wrap-around 2", "--wrap-around is incompatible with <monitor-pattern> argument"),
        ("move-workspace-to-display --wrap-around 2", "Unrecognized subcommand 'move-workspace-to-display'"), // The deprecated alias is gone
    ])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        expectEqual(output, .fail(error))
    }

    @Test
    func parseWrapAround() {
        expectEqual(parseMoveWorkspaceToMonitorTarget("move-workspace-to-monitor --wrap-around next"), .relative(.next))
    }

    // The test monitor is the only monitor
    @Test(arguments: singleMonitorErrors)
    func singleMonitor_noTargetMonitor(target: String, error: String) async {
        let workspace = focus.workspace
        let output = await runCmd("move-workspace-to-monitor \(target)")
        expectEqual(output, .fail(error))
        expectEqual(workspace.workspaceMonitor.monitorId_oneBased, mainMonitorInfo.monitorId_oneBased)
        expectEqual(focus.workspace, workspace)
    }

    @Test(arguments: ["--wrap-around next", "--wrap-around left", "main"])
    func singleMonitor_sameMonitor_succeedsSilently(target: String) async {
        let workspace = focus.workspace
        let output = await runCmd("move-workspace-to-monitor \(target)")
        expectEqual(output, .ok)
        expectEqual(focus.workspace, workspace)
        expectEqual(mainMonitorInfo.activeWorkspace, workspace)
    }

    /// No screens (e.g., during display reconfiguration) is a normal state, not a bug (RB-40)
    @Test
    func next_noScreens_failsWithMessage() async {
        let output = await $noScreensForTests.withValue(true) { await runCmd("move-workspace-to-monitor next") }
        expectEqual(output, .fail("Can't find the next monitor while there are no screens"))
    }
}

private func parseMoveWorkspaceToMonitorTarget(_ raw: String) -> MonitorTarget? {
    parsedCmd(raw, as: MoveWorkspaceToMonitorCommand.self)?.target
}
