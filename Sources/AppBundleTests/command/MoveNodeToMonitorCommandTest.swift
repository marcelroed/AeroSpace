@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct MoveNodeToMonitorCommandTest {
    @Test
    func parse() {
        testParseSingleCommandSucc("move-node-to-monitor next", MoveNodeToMonitorCommand(target: .relative(.next)))
        testParseSingleCommandSucc("move-node-to-monitor --fail-if-noop main", MoveNodeToMonitorCommand(target: .patterns([.main]), failIfNoop: true))
        testParseSingleCommandSucc("move-node-to-monitor -- next", MoveNodeToMonitorCommand(target: .patterns([.pattern("next")])))
        testParseSingleCommandSucc(
            "move-node-to-monitor -- main 2",
            MoveNodeToMonitorCommand(target: .patterns([.main, .sequenceNumber(2)])),
        )
        testParseSingleCommandSucc(
            "move-node-to-monitor --fail-if-noop -- next",
            MoveNodeToMonitorCommand(target: .patterns([.pattern("next")]), failIfNoop: true),
        )
    }

    @Test(arguments: [
        ("move-node-to-monitor --fail-if-noop next", "--fail-if-noop is incompatible with (left|down|up|right|next|prev)"),
        ("move-node-to-monitor --fail-if-noop left", "--fail-if-noop is incompatible with (left|down|up|right|next|prev)"),
        ("move-node-to-monitor --", "Argument '(left|down|up|right|next|prev|<monitor-pattern>)' is mandatory"),
    ] as [(String, String)])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        expectEqual(output, .fail(error))
    }

    // The test monitor is the only monitor
    @Test(arguments: singleMonitorErrors)
    func singleMonitor_noTargetMonitor(target: String, error: String) async {
        setUpTree("h_tiles(*1)")
        let output = await runCmd("move-node-to-monitor \(target)")
        expectEqual(output, .fail(error))
        expectEqual(describeTree(), "h_tiles(*1)")
    }

    @Test(arguments: ["--wrap-around next", "--wrap-around left", "main"])
    func singleMonitor_sameMonitor_isNoop(target: String) async {
        let workspace = setUpTree("h_tiles(*1)")
        let output = await runCmd("move-node-to-monitor \(target)")
        expectEqual(output, CmdOutput(stderr: ["Window '1' already belongs to workspace '\(workspace.name)'. Tip: use --fail-if-noop to exit with non-zero code"]))
        expectEqual(describeTree(), "h_tiles(*1)")
    }

    @Test
    func singleMonitor_sameMonitor_failIfNoop() async {
        setUpTree("h_tiles(*1)")
        let output = await runCmd("move-node-to-monitor --fail-if-noop main")
        expectEqual(output, .fail())
    }
}
