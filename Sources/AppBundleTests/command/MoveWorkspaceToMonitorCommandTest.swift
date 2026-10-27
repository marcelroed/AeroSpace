@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct MoveWorkspaceToMonitorCommandTest {
    @Test
    func parse() {
        #expect(parseMoveWorkspaceToMonitorTarget("move-workspace-to-monitor next") == .relative(.next))
        #expect(parseMoveWorkspaceToMonitorTarget("move-workspace-to-monitor main") == .patterns([.main]))
        #expect(parseMoveWorkspaceToMonitorTarget("move-workspace-to-monitor -- next") == .patterns([.pattern("next")!]))
    }

    @Test(arguments: [
        ("move-workspace-to-monitor --", "ERROR: Argument '(left|down|up|right|next|prev|<monitor-pattern>)' is mandatory"),
        // The deprecated move-workspace-to-display alias used to skip the post-parse validation (RB-12)
        ("move-workspace-to-monitor --wrap-around 2", "ERROR: --wrap-around is incompatible with <monitor-pattern> argument"),
        ("move-workspace-to-display --wrap-around 2", "ERROR: --wrap-around is incompatible with <monitor-pattern> argument"),
    ])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        #expect(output == .fail(error))
    }

    @Test(arguments: ["move-workspace-to-monitor", "move-workspace-to-display"])
    func parseDeprecatedAlias(command: String) {
        #expect(parseMoveWorkspaceToMonitorTarget("\(command) --wrap-around next") == .relative(.next))
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
    parsedArgs(raw, as: MoveWorkspaceToMonitorCmdArgs.self)?.target.val
}
