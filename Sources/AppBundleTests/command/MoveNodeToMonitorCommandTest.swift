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
        assertEquals(parseCommand("move-node-to-monitor --fail-if-noop next").errorOrNil, "--fail-if-noop is incompatible with (left|down|up|right|next|prev)")
        assertEquals(parseCommand("move-node-to-monitor --fail-if-noop left").errorOrNil, "--fail-if-noop is incompatible with (left|down|up|right|next|prev)")
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
            assertEquals(
                await parseCommand("move-node-to-monitor \(command)").cmdOrDie.run(.defaultEnv, .emptyStdin),
                CmdResult(stdout: [], stderr: [error], exitCode: Int32ExitCode(rawValue: 2)),
                additionalMsg: command,
            )
            assertEquals(root.layoutDescription, .h_tiles([.window(1)]))
        }
    }

    @Test
    func testSingleMonitor_sameMonitor_isNoop() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }
        for command in ["--wrap-around next", "--wrap-around left", "main"] {
            assertEquals(
                await parseCommand("move-node-to-monitor \(command)").cmdOrDie.run(.defaultEnv, .emptyStdin),
                CmdResult(
                    stdout: [],
                    stderr: ["Window '1' already belongs to workspace '\(name)'. Tip: use --fail-if-noop to exit with non-zero code"],
                    exitCode: Int32ExitCode(rawValue: 0),
                ),
                additionalMsg: command,
            )
            assertEquals(root.layoutDescription, .h_tiles([.window(1)]))
        }
        assertEquals(
            await parseCommand("move-node-to-monitor --fail-if-noop main").cmdOrDie.run(.defaultEnv, .emptyStdin),
            CmdResult(stdout: [], stderr: [], exitCode: Int32ExitCode(rawValue: 2)),
        )
    }
}
