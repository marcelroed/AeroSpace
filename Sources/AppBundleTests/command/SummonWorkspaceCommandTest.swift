@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct SummonWorkspaceCommandTest: AeroSpaceTestSuite {
    @Test
    func testParse() {
        assertEquals(parseCommand("summon-workspace").errorOrNil, "ERROR: Argument '<workspace>' is mandatory")
        testParseSingleCommandSucc("summon-workspace foo", SummonWorkspaceCmdArgs(rawArgs: []).copy(\.target, .initialized(.parse("foo").getOrDie())))
    }

    @Test
    func testParseDashDash() {
        testParseSingleCommandSucc(
            "summon-workspace -- foo",
            SummonWorkspaceCmdArgs(rawArgs: []).copy(\.target, .initialized(.parse("foo").getOrDie())),
        )
        testParseSingleCommandSucc(
            "summon-workspace --fail-if-noop -- foo",
            SummonWorkspaceCmdArgs(rawArgs: []).copy(\.target, .initialized(.parse("foo").getOrDie())).copy(\.failIfNoop, true),
        )
        assertEquals(parseCommand("summon-workspace --").errorOrNil, "ERROR: Argument '<workspace>' is mandatory")
        assertEquals(parseCommand("summon-workspace -- --fail-if-noop").errorOrNil, "ERROR: Workspace names starting with dash are disallowed")
    }

    @Test
    func testSummonToTheFocusedMonitor() async {
        let workspace = Workspace.get(byName: name)
        assertEquals(workspace.focusWorkspace(), true)
        assertEquals(
            await parseCommand("summon-workspace foo").cmdOrDie.run(.defaultEnv, .emptyStdin),
            CmdResult(stdout: [], stderr: [], exitCode: Int32ExitCode(rawValue: 0)),
        )
        let foo = Workspace.get(byName: "foo")
        assertEquals(mainMonitorInfo.activeWorkspace, foo)
        assertEquals(focus.workspace, foo)
        assertEquals(workspace.isVisible, false)
    }

    @Test
    func testAlreadyVisibleOnTheFocusedMonitor() async {
        let workspace = Workspace.get(byName: "bar")
        assertEquals(workspace.focusWorkspace(), true)
        assertEquals(
            await parseCommand("summon-workspace bar").cmdOrDie.run(.defaultEnv, .emptyStdin),
            CmdResult(
                stdout: [],
                stderr: ["Workspace 'bar' is already visible on the focused monitor. Tip: use --fail-if-noop to exit with non-zero code"],
                exitCode: Int32ExitCode(rawValue: 0),
            ),
        )
        assertEquals(
            await parseCommand("summon-workspace --fail-if-noop bar").cmdOrDie.run(.defaultEnv, .emptyStdin),
            CmdResult(stdout: [], stderr: [], exitCode: Int32ExitCode(rawValue: 2)),
        )
        assertEquals(focus.workspace, workspace)
    }
}
