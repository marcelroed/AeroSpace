@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct FocusMonitorCommandTest {
    /// `MonitorTarget.parse`, which `move-node-to-monitor` and `move-workspace-to-monitor` share
    @Test(arguments: [
        ("focus-monitor next", .success(.relative(.next))),
        ("focus-monitor left", .success(.direction(.left))),
        ("focus-monitor main", .success(.patterns([.main]))),
        ("focus-monitor -- next", .success(.patterns([.pattern(try CaseInsensitiveRegex("next"))]))),
        ("focus-monitor -- main 2", .success(.patterns([.main, .sequenceNumber(2)]))),
        ("focus-monitor --wrap-around main", .failure("--wrap-around is incompatible with <monitor-pattern> argument")),
        ("focus-monitor --", .failure("Argument '(left|down|up|right|next|prev|<monitor-pattern>)' is mandatory")),
    ] as [(String, Result<MonitorTarget, CmdParseError>)])
    func parse(command: String, expected: Result<MonitorTarget, CmdParseError>) {
        let target = parseCommand(command).flatMap { (shell: Shell<any Command>) -> Result<MonitorTarget, CmdParseError> in
            guard case .cmd(let command as FocusMonitorCommand) = shell else { return .failure("Not a focus-monitor command") }
            return .success(command.target)
        }
        expectEqual(target, expected)
    }

    /// The test monitor is the only monitor, so nothing changes
    @Test(arguments: ["focus-monitor", "move-node-to-monitor", "move-workspace-to-monitor"], [
        ("left", "No monitors in direction left"),
        ("down", "No monitors in direction down"),
        ("next", "Can't find target monitor"),
        ("prev", "Can't find target monitor"),
        ("2", "None of the monitors match the pattern(s)"),
        ("secondary", "None of the monitors match the pattern(s)"),
        ("2 secondary", "None of the monitors match the pattern(s)"),
    ] as [(String, String)])
    func singleMonitorNoTarget(command: String, target: (args: String, error: String)) async {
        let workspace = setUpTree("h_tiles(*1)")
        let output = await runCmd("\(command) \(target.args)")
        expectEqual(output, .fail(target.error))
        expectEqual(describeTree(), "h_tiles(*1)")
        expectEqual(focus.workspace, workspace)
        expectEqual(testMonitor.activeWorkspace, workspace)
    }

    @Test(arguments: ["--wrap-around next", "--wrap-around prev", "--wrap-around left", "main", "1"])
    func singleMonitor_focusesTheSameMonitor(target: String) async {
        let workspace = focus.workspace
        let output = await runCmd("focus-monitor \(target)")
        expectEqual(output, .ok)
        expectEqual(focus.workspace, workspace)
    }

    @Test(arguments: ["next", "right", "--wrap-around prev", "--wrap-around left", "2", "secondary"])
    func twoMonitors_focusesTheRightMonitor(target: String) async {
        updateMonitors([testMonitor, rightTestMonitor])
        let output = await runCmd("focus-monitor \(target)")
        expectEqual(output, .ok)
        expectEqual(focus.workspace, rightTestMonitor.activeWorkspace)
    }
}
