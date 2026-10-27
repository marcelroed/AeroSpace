@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct MoveNodeToMonitorCommandTest {
    @Test
    func parse() {
        testParseSingleCommandSucc("move-node-to-monitor next", MoveNodeToMonitorCmdArgs(target: .relative(.next)))
        testParseSingleCommandSucc("move-node-to-monitor --fail-if-noop main", MoveNodeToMonitorCmdArgs(target: .patterns([.main])).copy(\.failIfNoop, true))
        testParseSingleCommandSucc("move-node-to-monitor -- next", MoveNodeToMonitorCmdArgs(target: .patterns([.pattern("next")!])))
        testParseSingleCommandSucc(
            "move-node-to-monitor -- main 2",
            MoveNodeToMonitorCmdArgs(target: .patterns([.main, .sequenceNumber(2)])),
        )
        testParseSingleCommandSucc(
            "move-node-to-monitor --fail-if-noop -- next",
            MoveNodeToMonitorCmdArgs(target: .patterns([.pattern("next")!])).copy(\.failIfNoop, true),
        )
    }

    @Test(arguments: [
        ("move-node-to-monitor --fail-if-noop next", "ERROR: --fail-if-noop is incompatible with (left|down|up|right|next|prev)"),
        ("move-node-to-monitor --fail-if-noop left", "ERROR: --fail-if-noop is incompatible with (left|down|up|right|next|prev)"),
        ("move-node-to-monitor --", "ERROR: Argument '(left|down|up|right|next|prev|<monitor-pattern>)' is mandatory"),
    ])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        #expect(output == .fail(error))
    }

    // The test monitor is the only monitor
    @Test(arguments: singleMonitorErrors)
    func singleMonitor_noTargetMonitor(target: String, error: String) async {
        setUpTree("h_tiles(*1)")
        let output = await runCmd("move-node-to-monitor \(target)")
        #expect(output == .fail(error))
        #expect(describeTree() == "h_tiles(*1)")
    }

    @Test(arguments: ["--wrap-around next", "--wrap-around left", "main"])
    func singleMonitor_sameMonitor_isNoop(target: String) async {
        let workspace = setUpTree("h_tiles(*1)")
        let output = await runCmd("move-node-to-monitor \(target)")
        #expect(output == CmdOutput(stderr: ["Window '1' already belongs to workspace '\(workspace.name)'. Tip: use --fail-if-noop to exit with non-zero code"]))
        #expect(describeTree() == "h_tiles(*1)")
    }

    @Test
    func singleMonitor_sameMonitor_failIfNoop() async {
        setUpTree("h_tiles(*1)")
        let output = await runCmd("move-node-to-monitor --fail-if-noop main")
        #expect(output == .fail())
    }
}
