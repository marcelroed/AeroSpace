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
}

private func parseMoveWorkspaceToMonitorTarget(_ raw: String) -> MonitorTarget? {
    parsedArgs(raw, as: MoveWorkspaceToMonitorCmdArgs.self)?.target.val
}
