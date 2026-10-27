@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct MoveNodeToMonitorCommandTest {
    @Test(arguments: [
        ("move-node-to-monitor --fail-if-noop next", "--fail-if-noop is incompatible with (left|down|up|right|next|prev)"),
        ("move-node-to-monitor --fail-if-noop left", "--fail-if-noop is incompatible with (left|down|up|right|next|prev)"),
        ("move-node-to-monitor --", "Argument '(left|down|up|right|next|prev|<monitor-pattern>)' is mandatory"),
    ] as [(String, String)])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        expectEqual(output, .fail(error))
    }

    /// The test monitor is the only monitor
    @Test(arguments: [
        ("--wrap-around next", alreadyBelongs),
        ("--wrap-around left", alreadyBelongs),
        ("main", alreadyBelongs),
        ("--fail-if-noop main", .fail()),
    ] as [(String, CmdOutput)])
    func singleMonitor_sameMonitor_isNoop(target: String, expected: CmdOutput) async {
        setUpTree("h_tiles(*1)", workspace: "a")
        let output = await runCmd("move-node-to-monitor \(target)")
        expectEqual(output, expected)
        expectEqual(describeTree("a"), "h_tiles(*1)")
    }
}

nonisolated private let alreadyBelongs = CmdOutput(
    stderr: ["Window '1' already belongs to workspace 'a'. Tip: use --fail-if-noop to exit with non-zero code"],
)
