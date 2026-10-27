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

    /// The window enters next to the monitor it left: first when it moves right, last when it moves left. Across the target
    /// root's orientation, no side is next to that monitor: it enters last
    @Test(arguments: [
        ("right", "h_tiles(2 3)", "h_tiles(1 2 3)"),
        ("left", "h_tiles(2 3)", "h_tiles(2 3 1)"),
        ("right", "v_tiles(2 3)", "v_tiles(2 3 1)"),
    ] as [(String, String, String)])
    func twoMonitors_theWindowEntersOnTheSideItCameFrom(direction: String, targetTree: String, expected: String) async {
        updateMonitors([testMonitor, rightTestMonitor])
        let (source, target): (MonitorInfo, MonitorInfo) = direction == "right"
            ? (testMonitor, rightTestMonitor)
            : (rightTestMonitor, testMonitor)
        let targetWorkspace = target.activeWorkspace
        setUpTree(targetTree, workspace: targetWorkspace.name)
        setUpTree("h_tiles(*1)", workspace: source.activeWorkspace.name)
        let output = await runCmd("move-node-to-monitor \(direction)")
        expectEqual(output, .ok)
        expectEqual(describeTree(targetWorkspace.name), expected)
    }
}

nonisolated private let alreadyBelongs = CmdOutput(
    stderr: ["Window '1' already belongs to workspace 'a'. Tip: use --fail-if-noop to exit with non-zero code"],
)
