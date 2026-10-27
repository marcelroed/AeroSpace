@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct WorkspaceCommandTest {
    @Test
    func parse() {
        testParseSingleCommandSucc("workspace next", WorkspaceCmdArgs(target: .relative(.next)))
        testParseSingleCommandSucc("workspace --auto-back-and-forth W", WorkspaceCmdArgs(target: .direct(.parse("W").getOrDie()), autoBackAndForth: true))
        testParseSingleCommandSucc("workspace next --wrap-around", WorkspaceCmdArgs(target: .relative(.next), wrapAround: true))
        testParseSingleCommandSucc("workspace --stdin next", WorkspaceCmdArgs(target: .relative(.next)).copy(\.commonState.explicitStdinFlag, true))
        testParseSingleCommandSucc("workspace --no-stdin next", WorkspaceCmdArgs(target: .relative(.next)).copy(\.commonState.explicitStdinFlag, false))
        testParseSingleCommandSucc("workspace -- foo", WorkspaceCmdArgs(target: .direct(.parse("foo").getOrDie())))
        testParseSingleCommandSucc(
            "workspace --auto-back-and-forth -- foo",
            WorkspaceCmdArgs(target: .direct(.parse("foo").getOrDie()), autoBackAndForth: true),
        )
    }

    @Test(arguments: [
        ("workspace my mail", "ERROR: Unknown argument 'mail'"),
        ("workspace 'my mail'", "ERROR: Whitespace characters are forbidden in workspace names"),
        ("workspace", "ERROR: Argument '(<workspace-name>|next|prev)' is mandatory"),
        ("workspace --wrap-around W", "ERROR: --wrap-around requires using (next|prev) argument"),
        ("workspace --auto-back-and-forth next", "ERROR: --auto-back-and-forth is incompatible with (next|prev)"),
        ("workspace --stdin foo", "ERROR: --stdin and --no-stdin require using (next|prev) argument"),
        ("workspace -- next", "ERROR: 'next' is a reserved workspace name"),
        ("workspace --", "ERROR: Argument '(<workspace-name>|next|prev)' is mandatory"),
        ("workspace -- foo --fail-if-noop", "ERROR: Unknown argument '--fail-if-noop'"),
        ("workspace -- --help", "ERROR: Workspace names starting with dash are disallowed"),
    ])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        #expect(output == .fail(error))
    }

    /// From the focused workspace `from`, the command focuses the workspace `to`
    @Test(arguments: [
        ("a", "workspace b", "", CmdOutput.ok, "b"),
        ("a", "workspace a", "", CmdOutput(stderr: ["Workspace 'a' is already focused. Tip: use --fail-if-noop to exit with non-zero code"]), "a"),
        ("a", "workspace --fail-if-noop a", "", .fail(), "a"),
        // There is no previous workspace
        ("a", "workspace --auto-back-and-forth a", "", .fail("There is no previously focused workspace"), "a"),
        ("a", "workspace --stdin next", "a\nb\nc\n", .ok, "b"),
        ("b", "workspace --stdin prev", "a\nb\nc\n", .ok, "a"),
        ("c", "workspace --wrap-around --stdin next", "a\nb\nc\n", .ok, "a"),
        ("a", "workspace --wrap-around --stdin prev", "a\nb\nc\n", .ok, "c"),
        ("c", "workspace --stdin next", "a\nb\nc\n", .fail("Reached the end of the supplied workspaces list"), "c"),
        ("a", "workspace --stdin prev", "a\nb\nc\n", .fail("Reached the beginning of the supplied workspaces list"), "a"),
        ("a", "workspace --stdin next", "", .fail("The list of workspaces is empty"), "a"),
        // The focused workspace isn't in the list: next and prev land on its first workspace
        ("z", "workspace --stdin next", "a\nb\nc\n", .ok, "a"),
    ])
    func focusesWorkspace(from: String, command: String, stdin: String, expected: CmdOutput, to: String) async {
        #expect(Workspace.get(byName: from).focusWorkspace())
        let output = await runCmd(command, stdin: stdin)
        #expect(output == expected)
        #expect(focus.workspace.name == to)
    }

    @Test
    func autoBackAndForth_focusedTarget_focusesThePreviousWorkspace() async {
        _ = Workspace.get(byName: "b") // Alive
        #expect(Workspace.get(byName: "a").focusWorkspace())
        world.focusStore.prevWorkspaceName = "b"
        let output = await runCmd("workspace --auto-back-and-forth a")
        #expect(output == .ok)
        #expect(focus.workspace.name == "b")
    }

    @Test
    func autoBackAndForth_otherTarget_ignoresThePreviousWorkspace() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())
        world.focusStore.prevWorkspaceName = "c"
        let output = await runCmd("workspace --auto-back-and-forth b")
        #expect(output == .ok)
        #expect(focus.workspace.name == "b")
    }

    @Test
    func relativeWithoutStdin_picksFromAllWorkspaces() async {
        _ = Workspace.get(byName: "b") // Alive
        _ = Workspace.get(byName: "c")
        #expect(Workspace.get(byName: "a").focusWorkspace())
        let output = await runCmd("workspace next")
        #expect(output == .ok)
        #expect(focus.workspace.name == "b")
    }
}
