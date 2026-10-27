@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct MoveWorkspaceToMonitorCommandTest {
    @Test
    func parse() {
        #expect(parseMoveWorkspaceToMonitorTarget("move-workspace-to-monitor next") == .relative(.next))
        #expect(parseMoveWorkspaceToMonitorTarget("move-workspace-to-monitor main") == .patterns([.main]))
        #expect(parseMoveWorkspaceToMonitorTarget("move-workspace-to-monitor -- next") == .patterns([.pattern("next")!]))
    }

    @Test(arguments: [
        ("move-workspace-to-monitor --", "Argument '(left|down|up|right|next|prev|<monitor-pattern>)' is mandatory"),
        ("move-workspace-to-monitor --wrap-around 2", "--wrap-around is incompatible with <monitor-pattern> argument"),
        ("move-workspace-to-display --wrap-around 2", "Unrecognized subcommand 'move-workspace-to-display'"), // The deprecated alias is gone
    ])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        #expect(output == .fail(error))
    }

    @Test
    func parseWrapAround() {
        #expect(parseMoveWorkspaceToMonitorTarget("move-workspace-to-monitor --wrap-around next") == .relative(.next))
    }

    // The test monitor is the only monitor
    @Test(arguments: singleMonitorErrors)
    func singleMonitor_noTargetMonitor(target: String, error: String) async {
        let workspace = focus.workspace
        let output = await runCmd("move-workspace-to-monitor \(target)")
        #expect(output == .fail(error))
        #expect(workspace.workspaceMonitor.monitorId_oneBased == mainMonitorInfo.monitorId_oneBased)
        #expect(focus.workspace == workspace)
    }

    @Test(arguments: ["--wrap-around next", "--wrap-around left", "main"])
    func singleMonitor_sameMonitor_succeedsSilently(target: String) async {
        let workspace = focus.workspace
        let output = await runCmd("move-workspace-to-monitor \(target)")
        #expect(output == .ok)
        #expect(focus.workspace == workspace)
        #expect(mainMonitorInfo.activeWorkspace == workspace)
    }

    /// No screens (e.g., during display reconfiguration) is a normal state, not a bug (RB-40)
    @Test
    func next_noScreens_failsWithMessage() async {
        let output = await $noScreensForTests.withValue(true) { await runCmd("move-workspace-to-monitor next") }
        #expect(output == .fail("Can't find the next monitor while there are no screens"))
    }
}

private func parseMoveWorkspaceToMonitorTarget(_ raw: String) -> MonitorTarget? {
    parsedCmd(raw, as: MoveWorkspaceToMonitorCommand.self)?.target
}
