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

    @Test
    func testFocusMonitorInDirection_noMonitorThere() async {
        let result = await parseCommand("focus-monitor left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result, CmdResult(stdout: [], stderr: ["No monitors in direction left"], exitCode: .fail))
    }

    @Test
    func testFocusMonitorInDirection_noScreens_failsWithMessage() async {
        // No screens (e.g., during display reconfiguration) is a normal state, not a bug (RB-40)
        let result = await $noScreensForTests.withValue(true) {
            await parseCommand("focus-monitor left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        }
        assertEquals(result, CmdResult(stdout: [], stderr: ["Can't find monitors in direction left while there are no screens"], exitCode: .fail))
    }
}

private func parseFocusMonitorTarget(_ raw: String) -> MonitorTarget? {
    parsedArgs(raw, as: FocusMonitorCmdArgs.self)?.target.val
}
