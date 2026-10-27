@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct EchoCommandTest {
    @Test
    func parse() {
        testParseSingleCommandSucc("echo -- foo", EchoCommand(args: [[.literal("foo")]]))
        testParseSingleCommandSucc("echo foo", EchoCommand(args: [[.literal("foo")]]))
        testParseSingleCommandSucc("echo -- foo bar", EchoCommand(args: [[.literal("foo")], [.literal("bar")]]))
        testParseSingleCommandSucc("echo --stderr -- foo", EchoCommand(args: [[.literal("foo")]], isStderr: true))
        testParseSingleCommandSucc("echo --stderr foo", EchoCommand(args: [[.literal("foo")]], isStderr: true))
        testParseSingleCommandSucc("echo -- '%{window-id}'", EchoCommand(args: [[.interVar(.windowId)]]))
        testParseSingleCommandSucc("echo -- 'id: %{window-id}'", EchoCommand(args: [[.literal("id: "), .interVar(.windowId)]]))
        testParseSingleCommandSucc("echo -- --stderr", EchoCommand(args: [[.literal("--stderr")]]))
        testParseSingleCommandSucc("echo -- -h", EchoCommand(args: [[.literal("-h")]]))
        testParseSingleCommandSucc("echo -- --", EchoCommand(args: [[.literal("--")]]))

        testParseCommandHelp("echo -h")
        testParseCommandHelp("echo --help")
    }

    @Test(arguments: [
        ("echo", "Argument '<string>' is mandatory"),
        ("echo --", "Argument '<string>' is mandatory"),
        ("echo --foo", "Unknown flag '--foo'"),
        ("echo -- %{foo}", "Can't parse 'foo'.\nPossible values: (window-id|window-is-fullscreen|window-title|window-layout|window-parent-container-layout|workspace|workspace-is-focused|workspace-is-visible|workspace-root-container-layout|app-bundle-id|app-name|app-pid|app-exec-path|app-bundle-path|monitor-id|monitor-appkit-nsscreen-screens-id|monitor-name|monitor-is-main|right-padding|newline|tab)"),
    ])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        expectEqual(output, .fail(error))
    }

    @Test(arguments: [
        ("h_tiles()", "echo -- foo", CmdOutput(stdout: ["foo"])),
        ("h_tiles()", "echo -- foo bar baz", CmdOutput(stdout: ["foo", "bar", "baz"])),
        ("h_tiles()", "echo --stderr -- foo", CmdOutput(stderr: ["foo"])),
        ("h_tiles(*1)", "echo -- '%{window-id}'", CmdOutput(stdout: ["1"])),
        ("h_tiles()", "echo -- '%{window-id}'", .fail("No window is focused")),
        // The first error wins: one line, not one per variable
        ("h_tiles()", "echo -- '%{window-id} %{app-name}'", .fail("No window is focused")),
        ("h_tiles(*42)", "echo -- 'id: %{window-id}'", CmdOutput(stdout: ["id: 42"])),
        ("h_tiles(*5)", "echo --stderr -- '%{window-id}'", CmdOutput(stderr: ["5"])),
    ])
    func run(tree: String, command: String, expected: CmdOutput) async {
        setUpTree(tree)
        let output = await runCmd(command)
        expectEqual(output, expected)
    }

    @Test
    func workspaceInterpolation() async {
        let output = await runCmd("echo -- '%{workspace}'")
        expectEqual(output, CmdOutput(stdout: [focus.workspace.name]))
    }
}
