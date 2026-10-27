@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct MoveNodeToMonitorCommandTest: AeroSpaceTestSuite {
    @Test
    func testParse() {
        testParseSingleCommandSucc("move-node-to-monitor next", MoveNodeToMonitorCmdArgs(target: .relative(.next)))
        testParseSingleCommandSucc("move-node-to-monitor --fail-if-noop main", MoveNodeToMonitorCmdArgs(target: .patterns([.main])).copy(\.failIfNoop, true))
        assertEquals(parseCommand("move-node-to-monitor --fail-if-noop next").errorOrNil, "ERROR: --fail-if-noop is incompatible with (left|down|up|right|next|prev)")
        assertEquals(parseCommand("move-node-to-monitor --fail-if-noop left").errorOrNil, "ERROR: --fail-if-noop is incompatible with (left|down|up|right|next|prev)")
    }

    @Test
    func testParseDashDash() {
        testParseSingleCommandSucc("move-node-to-monitor -- next", MoveNodeToMonitorCmdArgs(target: .patterns([.pattern("next")!])))
        testParseSingleCommandSucc(
            "move-node-to-monitor -- main 2",
            MoveNodeToMonitorCmdArgs(target: .patterns([.main, .sequenceNumber(2)])),
        )
        testParseSingleCommandSucc(
            "move-node-to-monitor --fail-if-noop -- next",
            MoveNodeToMonitorCmdArgs(target: .patterns([.pattern("next")!])).copy(\.failIfNoop, true),
        )
        assertEquals(parseCommand("move-node-to-monitor --").errorOrNil, "ERROR: Argument \'(left|down|up|right|next|prev|<monitor-pattern>)\' is mandatory")
    }

    // The test monitor is the only monitor
    @Test
    func testSingleMonitor_noTargetMonitor() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }
        for (command, error) in singleMonitorErrors {
            await assertRun("move-node-to-monitor \(command)", exitCode: 2, stdout: [], stderr: [error])
            assertEquals(root.layoutDescription, .h_tiles([.window(1)]))
        }
    }

    @Test
    func testSingleMonitor_sameMonitor_isNoop() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }
        for command in ["--wrap-around next", "--wrap-around left", "main"] {
            await assertRun(
                "move-node-to-monitor \(command)",
                exitCode: 0,
                stdout: [],
                stderr: ["Window '1' already belongs to workspace '\(name)'. Tip: use --fail-if-noop to exit with non-zero code"],
            )
            assertEquals(root.layoutDescription, .h_tiles([.window(1)]))
        }
        await assertRun("move-node-to-monitor --fail-if-noop main", exitCode: 2, stdout: [], stderr: [])
    }
}
