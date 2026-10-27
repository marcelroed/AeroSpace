@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct FocusMonitorCommandTest: AeroSpaceTestSuite {
    @Test
    func testParse() {
        assertEquals(parseFocusMonitorTarget("focus-monitor next"), .relative(.next))
        assertEquals(parseFocusMonitorTarget("focus-monitor left"), .direction(.left))
        assertEquals(parseFocusMonitorTarget("focus-monitor main"), .patterns([.main]))
        assertEquals(parseCommand("focus-monitor --wrap-around main").errorOrNil, "--wrap-around is incompatible with <monitor-pattern> argument")
    }

    @Test
    func testParseDashDash() {
        assertEquals(parseFocusMonitorTarget("focus-monitor -- next"), .patterns([.pattern("next")!]))
        assertEquals(parseFocusMonitorTarget("focus-monitor -- main 2"), .patterns([.main, .sequenceNumber(2)]))
        assertEquals(parseCommand("focus-monitor --").errorOrNil, "ERROR: Argument \'(left|down|up|right|next|prev|<monitor-pattern>)\' is mandatory")
    }

    // The test monitor is the only monitor
    @Test
    func testSingleMonitor_noTargetMonitor() async {
        for (command, error) in singleMonitorErrors {
            await assertRun("focus-monitor \(command)", exitCode: 2, stdout: [], stderr: [error])
        }
    }

    @Test
    func testSingleMonitor_focusesTheSameMonitor() async {
        let workspace = Workspace.get(byName: name)
        assertEquals(workspace.focusWorkspace(), true)
        for command in ["--wrap-around next", "--wrap-around prev", "--wrap-around left", "main", "1"] {
            await assertRun("focus-monitor \(command)", exitCode: 0, stdout: [], stderr: [])
            assertEquals(focus.workspace, workspace)
        }
    }
}

/// The arguments of the monitor commands that find no monitor when there is only one monitor, and the errors
let singleMonitorErrors: [(String, String)] = [
    ("left", "No monitors in direction left"),
    ("down", "No monitors in direction down"),
    ("next", "Can't find target monitor"),
    ("prev", "Can't find target monitor"),
    ("secondary", "None of the monitors match the pattern(s)"),
    ("2 secondary", "None of the monitors match the pattern(s)"),
]

private func parseFocusMonitorTarget(_ raw: String) -> MonitorTarget? {
    parsedArgs(raw, as: FocusMonitorCmdArgs.self)?.target.val
}
