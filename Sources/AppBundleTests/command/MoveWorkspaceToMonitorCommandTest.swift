@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct MoveWorkspaceToMonitorCommandTest: AeroSpaceTestSuite {
    @Test
    func testParse() {
        assertEquals(parseMoveWorkspaceToMonitorTarget("move-workspace-to-monitor next"), .relative(.next))
        assertEquals(parseMoveWorkspaceToMonitorTarget("move-workspace-to-monitor main"), .patterns([.main]))
    }

    @Test
    func testParseDashDash() {
        assertEquals(parseMoveWorkspaceToMonitorTarget("move-workspace-to-monitor -- next"), .patterns([.pattern("next")!]))
        assertEquals(parseCommand("move-workspace-to-monitor --").errorOrNil, "ERROR: Argument \'(left|down|up|right|next|prev|<monitor-pattern>)\' is mandatory")
    }

    // The test monitor is the only monitor
    @Test
    func testSingleMonitor_noTargetMonitor() async {
        let workspace = Workspace.get(byName: name)
        assertEquals(workspace.focusWorkspace(), true)
        for (command, error) in singleMonitorErrors {
            await assertRun("move-workspace-to-monitor \(command)", exitCode: 2, stdout: [], stderr: [error])
            assertEquals(workspace.workspaceMonitor.monitorId_oneBased, mainMonitorInfo.monitorId_oneBased)
            assertEquals(focus.workspace, workspace)
        }
    }

    @Test
    func testSingleMonitor_sameMonitor_succeedsSilently() async {
        let workspace = Workspace.get(byName: name)
        assertEquals(workspace.focusWorkspace(), true)
        for command in ["--wrap-around next", "--wrap-around left", "main"] {
            await assertRun("move-workspace-to-monitor \(command)", exitCode: 0, stdout: [], stderr: [])
            assertEquals(focus.workspace, workspace)
            assertEquals(mainMonitorInfo.activeWorkspace, workspace)
        }
    }

    @Test
    func testParseDeprecatedAliasIsValidatedLikeTheCommand() {
        // The deprecated move-workspace-to-display alias used to skip the post-parse validation (RB-12)
        for command in ["move-workspace-to-monitor", "move-workspace-to-display"] {
            assertEquals(parseCommand("\(command) --wrap-around 2").errorOrNil, "ERROR: --wrap-around is incompatible with <monitor-pattern> argument")
            assertEquals(parseMoveWorkspaceToMonitorTarget("\(command) --wrap-around next"), .relative(.next))
        }
    }

    @Test
    func testMoveWorkspaceToMonitorNext_noScreens_failsWithMessage() async {
        // No screens (e.g., during display reconfiguration) is a normal state, not a bug (RB-40)
        let result = await $noScreensForTests.withValue(true) {
            await parseCommand("move-workspace-to-monitor next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        }
        assertEquals(result, CmdResult(stdout: [], stderr: ["Can't find the next monitor while there are no screens"], exitCode: .fail))
    }
}

private func parseMoveWorkspaceToMonitorTarget(_ raw: String) -> MonitorTarget? {
    parsedArgs(raw, as: MoveWorkspaceToMonitorCmdArgs.self)?.target.val
}
