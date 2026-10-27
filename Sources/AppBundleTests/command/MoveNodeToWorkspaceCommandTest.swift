@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct MoveNodeToWorkspaceCommandTest {
    @Test
    func parse() throws {
        testParseSingleCommandSucc("move-node-to-workspace next", MoveNodeToWorkspaceCommand(target: .relative(.next)))
        testParseSingleCommandSucc("move-node-to-workspace --stdin next", MoveNodeToWorkspaceCommand(target: .relative(.next, useStdin: true)))
        testParseSingleCommandSucc("move-node-to-workspace -- foo", MoveNodeToWorkspaceCommand(target: .direct(try .parse("foo"))))
        testParseSingleCommandSucc(
            "move-node-to-workspace --focus-follows-window -- foo",
            MoveNodeToWorkspaceCommand(target: .direct(try .parse("foo")), focusFollowsWindow: true),
        )
        testParseSingleCommandSucc(
            "move-node-to-workspace --fail-if-noop --window-id 2 foo",
            MoveNodeToWorkspaceCommand(target: .direct(try .parse("foo"), failIfNoop: true, windowId: 2)),
        )
    }

    @Test(arguments: [
        ("move-node-to-workspace --fail-if-noop next", "--fail-if-noop is incompatible with (next|prev)"),
        ("move-node-to-workspace --stdin foo", "--stdin requires using (next|prev) argument"),
        ("move-node-to-workspace --wrap-around W", "--wrap-around requires using (next|prev) argument"),
        ("move-node-to-workspace -- prev", "'prev' is a reserved workspace name"),
        ("move-node-to-workspace --", "Argument '(<workspace-name>|next|prev)' is mandatory"),
    ] as [(String, String)])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        expectEqual(output, .fail(error))
    }

    /// The window moves from the focused workspace 'a' to `target`
    @Test(arguments: [
        ("h_tiles(*1)", "move-node-to-workspace b", "", "b", "h_tiles(1)"),
        ("h_tiles() floating(*1)", "move-node-to-workspace b", "", "b", "h_tiles() floating(1)"), // Stays floating
        // 'b' is alive, so it's the next workspace
        ("h_tiles(*1)", "move-node-to-workspace next", "", "b", "h_tiles(1)"),
        // Workspaces from stdin. --wrap-around makes them independent of the alive workspaces
        ("h_tiles(*1)", "move-node-to-workspace --wrap-around --stdin prev", "a\nb\n", "b", "h_tiles(1)"),
        ("h_tiles(*1)", "move-node-to-workspace --stdin next", "a\nx\ny\n", "x", "h_tiles(1)"),
    ] as [(String, String, String, String, String)])
    func movesTheLastWindow(tree: String, command: String, stdin: String, target: String, targetTree: String) async {
        setUpTree(tree, workspace: "a")
        _ = Workspace.get(byName: "b") // Alive
        let output = await runCmd(command, stdin: stdin)
        expectEqual(output, .ok)
        expectEqual(focus.workspace.name, "a") // The focus stays on the empty workspace
        expectEqual(describeTree("a"), "h_tiles()")
        expectEqual(describeTree(target), targetTree)
    }

    @Test
    func focusesTheMostRecentWindowThatStays() async {
        setUpTree("h_tiles(1 *2)", workspace: "a")
        let output = await runCmd("move-node-to-workspace b")
        expectEqual(output, .ok)
        expectEqual(describeTree("a"), "h_tiles(*1)")
        expectEqual(describeTree("b"), "h_tiles(2)")
    }

    @Test
    func focusFollowsWindow() async {
        let source = setUpTree("h_tiles(*1)", workspace: "a") // Held: get(byName:) would recreate a collected workspace
        let output = await runCmd("move-node-to-workspace --focus-follows-window b")
        expectEqual(output, .ok)
        expectEqual(focus.workspace.name, "b")
        expectEqual(describeTree("b"), "h_tiles(*1)")
        #expect(source.isEffectivelyEmpty)
    }

    @Test
    func summonWindow() async {
        setUpTree("h_tiles(*1)", workspace: "a")
        let source = setUpTree("h_tiles(2)", workspace: "b") // Held: get(byName:) would recreate a collected workspace
        let output = await runCmd("move-node-to-workspace --window-id 2 a")
        expectEqual(output, .ok)
        expectEqual(describeTree("a"), "h_tiles(*1 2)")
        #expect(source.isEffectivelyEmpty)
    }

    @Test
    func noWindowIsFocused() async {
        let output = await runCmd("move-node-to-workspace b")
        expectEqual(output, .fail("No window is focused"))
    }

    @Test(arguments: [
        ("move-node-to-workspace a", CmdOutput(stderr: ["Window '1' already belongs to workspace 'a'. Tip: use --fail-if-noop to exit with non-zero code"])),
        ("move-node-to-workspace --fail-if-noop a", .fail()),
        // 'a' is the first workspace
        ("move-node-to-workspace prev", .fail("Reached the beginning of the supplied workspaces list")),
    ] as [(String, CmdOutput)])
    func noop(command: String, expected: CmdOutput) async {
        setUpTree("h_tiles(*1)", workspace: "a")
        let output = await runCmd(command)
        expectEqual(output, expected)
        expectEqual(describeTree("a"), "h_tiles(*1)")
    }
}
