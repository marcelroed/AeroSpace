@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct FocusMonitorCommandTest {
    @Test
    func parse() {
        #expect(parseFocusMonitorTarget("focus-monitor next") == .relative(.next))
        #expect(parseFocusMonitorTarget("focus-monitor left") == .direction(.left))
        #expect(parseFocusMonitorTarget("focus-monitor main") == .patterns([.main]))
        #expect(parseFocusMonitorTarget("focus-monitor -- next") == .patterns([.pattern("next")]))
        #expect(parseFocusMonitorTarget("focus-monitor -- main 2") == .patterns([.main, .sequenceNumber(2)]))
    }

    @Test(arguments: [
        ("focus-monitor --wrap-around main", "--wrap-around is incompatible with <monitor-pattern> argument"),
        ("focus-monitor --", "Argument '(left|down|up|right|next|prev|<monitor-pattern>)' is mandatory"),
    ])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        #expect(output == .fail(error))
    }

    // The test monitor is the only monitor
    @Test(arguments: singleMonitorErrors + [("2", "None of the monitors match the pattern(s)")])
    func singleMonitor_noTargetMonitor(target: String, error: String) async {
        let output = await runCmd("focus-monitor \(target)")
        #expect(output == .fail(error))
    }

    @Test(arguments: ["--wrap-around next", "--wrap-around prev", "--wrap-around left", "main", "1"])
    func singleMonitor_focusesTheSameMonitor(target: String) async {
        let workspace = focus.workspace
        let output = await runCmd("focus-monitor \(target)")
        #expect(output == .ok)
        #expect(focus.workspace == workspace)
    }

    /// No screens (e.g., during display reconfiguration) is a normal state, not a bug (RB-40)
    @Test(arguments: [
        ("focus-monitor left", "Can't find monitors in direction left while there are no screens"),
        ("focus-monitor next", "Can't find the next monitor while there are no screens"),
        ("focus-monitor --wrap-around next", "Can't find the next monitor while there are no screens"),
        ("focus-monitor prev", "Can't find the prev monitor while there are no screens"),
        // With screens, both patterns match "Test Monitor"
        ("focus-monitor 1", "Can't find monitors that match the pattern(s) while there are no screens"),
        ("focus-monitor test", "Can't find monitors that match the pattern(s) while there are no screens"),
    ])
    func noScreens_failsWithMessage(command: String, error: String) async {
        let output = await $noScreensForTests.withValue(true) { await runCmd(command) }
        #expect(output == .fail(error))
    }
}

/// The targets of the monitor commands that find no monitor when there is only one monitor, and the errors
nonisolated let singleMonitorErrors: [(String, String)] = [
    ("left", "No monitors in direction left"),
    ("down", "No monitors in direction down"),
    ("next", "Can't find target monitor"),
    ("prev", "Can't find target monitor"),
    ("secondary", "None of the monitors match the pattern(s)"),
    ("2 secondary", "None of the monitors match the pattern(s)"),
]

private func parseFocusMonitorTarget(_ raw: String) -> MonitorTarget? {
    parsedCmd(raw, as: FocusMonitorCommand.self)?.target
}
