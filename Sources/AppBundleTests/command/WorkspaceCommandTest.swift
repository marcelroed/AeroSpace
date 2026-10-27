@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct WorkspaceCommandTest {
    @Test
    func parse() throws {
        testParseSingleCommandSucc("workspace next", WorkspaceCommand(target: .relative(.next)))
        testParseSingleCommandSucc("workspace --auto-back-and-forth W", WorkspaceCommand(target: .direct(try .parse("W"), whenFocused: .backAndForth)))
        testParseSingleCommandSucc("workspace next --wrap-around", WorkspaceCommand(target: .relative(.next, wrapAround: true)))
        testParseSingleCommandSucc("workspace --stdin next", WorkspaceCommand(target: .relative(.next, useStdin: true)))
        testParseSingleCommandSucc("workspace -- foo", WorkspaceCommand(target: .direct(try .parse("foo"))))
        testParseSingleCommandSucc(
            "workspace --auto-back-and-forth -- foo",
            WorkspaceCommand(target: .direct(try .parse("foo"), whenFocused: .backAndForth)),
        )
        testParseSingleCommandSucc("workspace --fail-if-noop W", WorkspaceCommand(target: .direct(try .parse("W"), whenFocused: .fail)))
    }

    @Test(arguments: [
        ("workspace my mail", "Unknown argument 'mail'"),
        ("workspace 'my mail'", "Whitespace characters are forbidden in workspace names"),
        ("workspace", "Argument '(<workspace-name>|next|prev)' is mandatory"),
        ("workspace --wrap-around W", "--wrap-around requires using (next|prev) argument"),
        ("workspace --auto-back-and-forth next", "--auto-back-and-forth is incompatible with (next|prev)"),
        ("workspace --stdin foo", "--stdin requires using (next|prev) argument"),
        ("workspace -- next", "'next' is a reserved workspace name"),
        ("workspace --", "Argument '(<workspace-name>|next|prev)' is mandatory"),
        ("workspace -- foo --fail-if-noop", "Unknown argument '--fail-if-noop'"),
        ("workspace -- --help", "Workspace names starting with dash are disallowed"),
    ] as [(String, String)])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        expectEqual(output, .fail(error))
    }

    /// From the focused workspace `from`, the command focuses the workspace `to`
    @Test(arguments: [
        ("a", "workspace b", "", .ok, "b"),
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
    ] as [(String, String, String, CmdOutput, String)])
    func focusesWorkspace(from: String, command: String, stdin: String, expected: CmdOutput, to: String) async {
        #expect(Workspace.get(byName: from).focusWorkspace())
        let output = await runCmd(command, stdin: stdin)
        expectEqual(output, expected)
        expectEqual(focus.workspace.name, to)
    }

    @Test
    func autoBackAndForth_focusedTarget_focusesThePreviousWorkspace() async {
        _ = Workspace.get(byName: "b") // Alive
        #expect(Workspace.get(byName: "a").focusWorkspace())
        world.focusStore.prevWorkspaceName = "b"
        let output = await runCmd("workspace --auto-back-and-forth a")
        expectEqual(output, .ok)
        expectEqual(focus.workspace.name, "b")
    }

    @Test
    func autoBackAndForth_otherTarget_ignoresThePreviousWorkspace() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())
        world.focusStore.prevWorkspaceName = "c"
        let output = await runCmd("workspace --auto-back-and-forth b")
        expectEqual(output, .ok)
        expectEqual(focus.workspace.name, "b")
    }

    @Test
    func relativeWithoutStdin_picksFromAllWorkspaces() async {
        _ = Workspace.get(byName: "b") // Alive
        _ = Workspace.get(byName: "c")
        #expect(Workspace.get(byName: "a").focusWorkspace())
        let output = await runCmd("workspace next")
        expectEqual(output, .ok)
        expectEqual(focus.workspace.name, "b")
    }

    /// The AX work of a switch: each window of the shown workspace gets one frame write, each window of the hidden one is
    /// parked once, and no window gets both
    @Test
    func switchingWorkspacesWritesTheShownWindowsAndParksTheHiddenOnes() async throws {
        setUpTree("h_tiles(1 2)", workspace: "a")
        setUpTree("h_tiles(3)", workspace: "b")
        for id: WindowId in [1, 2, 3] {
            testWindow(id).rect = rect(0, 0, 100, 100)
        }
        #expect(Workspace.get(byName: "a").focusWorkspace())
        try await layoutWorkspaces()
        fake.resetCalls()

        expectEqual(await runCmd("workspace b"), .ok)
        try await layoutWorkspaces()

        expectEqual(fake.calls(of: .frame).map(\.windowId), [3])
        expectEqual(fake.calls(of: .park).map(\.windowId), [1, 2])
        expectEqual(([1, 2, 3] as [WindowId]).map { fake.windows[$0]?.parked != nil }, [true, true, false])
        // The parks read where the windows were, to put them back there. Nothing else reads
        expectEqual(fake.calls.filter { ![.frame, .park].contains($0.kind) }, [.observedRect(1), .observedRect(2)])
    }
}
