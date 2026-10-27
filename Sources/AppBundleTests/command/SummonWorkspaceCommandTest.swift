@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct SummonWorkspaceCommandTest {
    @Test
    func parse() throws {
        testParseSingleCommandSucc("summon-workspace foo", SummonWorkspaceCommand(target: try .parse("foo")))
        testParseSingleCommandSucc(
            "summon-workspace -- foo",
            SummonWorkspaceCommand(target: try .parse("foo")),
        )
        testParseSingleCommandSucc(
            "summon-workspace --fail-if-noop -- foo",
            SummonWorkspaceCommand(target: try .parse("foo"), failIfNoop: true),
        )
    }

    @Test(arguments: [
        ("summon-workspace", "Argument '<workspace>' is mandatory"),
        ("summon-workspace --", "Argument '<workspace>' is mandatory"),
        ("summon-workspace -- --fail-if-noop", "Workspace names starting with dash are disallowed"),
    ] as [(String, String)])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        expectEqual(output, .fail(error))
    }

    @Test
    func summonsToTheFocusedMonitor() async {
        let workspace = focus.workspace
        let output = await runCmd("summon-workspace foo")
        expectEqual(output, .ok)
        let foo = Workspace.get(byName: "foo")
        expectEqual(mainMonitorInfo.activeWorkspace, foo)
        expectEqual(focus.workspace, foo)
        #expect(!workspace.isVisible)
    }

    @Test(arguments: [
        ("summon-workspace bar", CmdOutput(stderr: ["Workspace 'bar' is already visible on the focused monitor. Tip: use --fail-if-noop to exit with non-zero code"])),
        ("summon-workspace --fail-if-noop bar", .fail()),
    ] as [(String, CmdOutput)])
    func alreadyVisibleOnTheFocusedMonitor(command: String, expected: CmdOutput) async {
        let workspace = Workspace.get(byName: "bar")
        #expect(workspace.focusWorkspace())
        let output = await runCmd(command)
        expectEqual(output, expected)
        expectEqual(focus.workspace, workspace)
    }
}
