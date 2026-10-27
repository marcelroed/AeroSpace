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
        assertEquals(parseCommand("focus-monitor --wrap-around main").errorOrNil, "ERROR: --wrap-around is incompatible with <monitor-pattern> argument")
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

    @Test
    func testFocusMonitorInDirection_noMonitorThere() async {
        await assertRun("focus-monitor left", exitCode: 2, stdout: [], stderr: ["No monitors in direction left"])
    }

    @Test
    func testFocusMonitorInDirection_noScreens_failsWithMessage() async {
        // No screens (e.g., during display reconfiguration) is a normal state, not a bug (RB-40)
        await $noScreensForTests.withValue(true) {
            await assertRun("focus-monitor left", exitCode: 2, stdout: [], stderr: ["Can't find monitors in direction left while there are no screens"])
        }
    }

    @Test
    func testFocusMonitorNextPrev_noScreens_failsWithMessage() async {
        // No screens (e.g., during display reconfiguration) is a normal state, not a bug (RB-40)
        for (command, expected) in [
            ("focus-monitor next", "Can't find the next monitor while there are no screens"),
            ("focus-monitor --wrap-around next", "Can't find the next monitor while there are no screens"),
            ("focus-monitor prev", "Can't find the prev monitor while there are no screens"),
        ] {
            await $noScreensForTests.withValue(true) {
                await assertRun(command, exitCode: 2, stdout: [], stderr: [expected])
            }
        }
    }

    @Test
    func testFocusMonitorPattern_noMonitorMatches() async {
        await assertRun("focus-monitor 2", exitCode: 2, stdout: [], stderr: ["None of the monitors match the pattern(s)"])
    }

    @Test
    func testFocusMonitorPattern_noScreens_failsWithMessage() async {
        // With screens, both patterns match "Test Monitor". Without them, no monitor matches, and it's not a user error (RB-40)
        for command in ["focus-monitor 1", "focus-monitor test"] {
            await $noScreensForTests.withValue(true) {
                await assertRun(command, exitCode: 2, stdout: [], stderr: ["Can't find monitors that match the pattern(s) while there are no screens"])
            }
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
