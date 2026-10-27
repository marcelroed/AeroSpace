@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct EchoCommandTest {
    @Test
    func parse() {
        testParseSingleCommandSucc(
            "echo -- foo",
            EchoCmdArgs(rawArgs: []).copy(\.args, .initialized([[.literal("foo")]])),
        )
        testParseSingleCommandSucc(
            "echo -- foo bar",
            EchoCmdArgs(rawArgs: []).copy(\.args, .initialized([[.literal("foo")], [.literal("bar")]])),
        )
        testParseSingleCommandSucc(
            "echo --stderr -- foo",
            EchoCmdArgs(rawArgs: [])
                .copy(\.args, .initialized([[.literal("foo")]]))
                .copy(\.isStderr, true),
        )
        testParseSingleCommandSucc(
            "echo -- '%{window-id}'",
            EchoCmdArgs(rawArgs: []).copy(\.args, .initialized([[.interVar(.formatVar(.window(.windowId)))]])),
        )
        testParseSingleCommandSucc(
            "echo -- 'id: %{window-id}'",
            EchoCmdArgs(rawArgs: []).copy(\.args, .initialized([[.literal("id: "), .interVar(.formatVar(.window(.windowId)))]])),
        )
        testParseSingleCommandSucc(
            "echo -- --stderr",
            EchoCmdArgs(rawArgs: []).copy(\.args, .initialized([[.literal("--stderr")]])),
        )
        testParseSingleCommandSucc(
            "echo -- -h",
            EchoCmdArgs(rawArgs: []).copy(\.args, .initialized([[.literal("-h")]])),
        )

        testParseCommandHelp("echo -h")
        testParseCommandHelp("echo --help")
    }

    @Test(arguments: [
        ("echo", "ERROR: Argument '--' is mandatory\nERROR: Argument '<string>' is mandatory"),
        ("echo --", "ERROR: Argument '<string>' is mandatory"),
        ("echo foo", "ERROR: Expected: --. Got: 'foo'"),
        ("echo --stderr foo", "ERROR: Expected: --. Got: 'foo'"),
        ("echo -- %{foo}", "ERROR: Can't parse 'foo'.\n       Possible values: (window-id|window-is-fullscreen|window-title|window-layout|window-parent-container-layout|workspace|workspace-is-focused|workspace-is-visible|workspace-root-container-layout|app-bundle-id|app-name|app-pid|app-exec-path|app-bundle-path|monitor-id|monitor-appkit-nsscreen-screens-id|monitor-name|monitor-is-main|right-padding|newline|tab)"),
    ])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        #expect(output == .fail(error))
    }

    @Test(arguments: [
        ("h_tiles()", "echo -- foo", CmdOutput(stdout: ["foo"])),
        ("h_tiles()", "echo -- foo bar baz", CmdOutput(stdout: ["foo", "bar", "baz"])),
        ("h_tiles()", "echo --stderr -- foo", CmdOutput(stderr: ["foo"])),
        ("h_tiles(*1)", "echo -- '%{window-id}'", CmdOutput(stdout: ["1"])),
        ("h_tiles()", "echo -- '%{window-id}'", .fail("No window is focused")),
        ("h_tiles(*42)", "echo -- 'id: %{window-id}'", CmdOutput(stdout: ["id: 42"])),
        ("h_tiles(*5)", "echo --stderr -- '%{window-id}'", CmdOutput(stderr: ["5"])),
    ])
    func run(tree: String, command: String, expected: CmdOutput) async {
        setUpTree(tree)
        let output = await runCmd(command)
        #expect(output == expected)
    }

    @Test
    func workspaceInterpolation() async {
        let output = await runCmd("echo -- '%{workspace}'")
        #expect(output == CmdOutput(stdout: [focus.workspace.name]))
    }
}
