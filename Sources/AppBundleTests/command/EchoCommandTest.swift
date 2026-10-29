@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct EchoCommandTest {
    /// `tree` is the focused workspace, "setUpWorkspacesForTests". Without a focused window, `echo` describes the workspace
    @Test(arguments: [
        ("h_tiles()", "echo foo", CmdOutput(stdout: ["foo"])),
        ("h_tiles()", "echo -- foo bar baz", CmdOutput(stdout: ["foo", "bar", "baz"])),
        ("h_tiles()", "echo --stderr foo", CmdOutput(stderr: ["foo"])),
        // After `--`, options are text
        ("h_tiles()", "echo -- --stderr -h --", CmdOutput(stdout: ["--stderr", "-h", "--"])),
        ("h_tiles(*42)", "echo -- 'id: %{window-id}'", CmdOutput(stdout: ["id: 42"])),
        ("h_tiles(*5)", "echo --stderr -- '%{window-id}'", CmdOutput(stderr: ["5"])),
        ("h_tiles(*1)", "echo '%{window-title}' '%{workspace}%{tab}%{monitor-name}'", CmdOutput(stdout: ["TestWindow(1)", "setUpWorkspacesForTests\tTest Monitor"])),
        ("h_tiles(1 *2)", "echo --window-id 1 '%{window-id}'", CmdOutput(stdout: ["1"])),
        ("h_tiles()", "echo 'a%{right-padding}b'", CmdOutput(stdout: ["ab"])), // A single line has nothing to pad
        ("h_tiles()", "echo '%{workspace} %{workspace-is-focused}'", CmdOutput(stdout: ["setUpWorkspacesForTests true"])),
        ("h_tiles()", "echo -- '%{window-id}'", .fail(noWindowIsFocused)),
        // The first error wins: one line, not one per variable
        ("h_tiles()", "echo -- '%{window-id} %{app-name}'", .fail(noWindowIsFocused)),
        ("h_tiles(*1)", "echo --window-id 2 foo", .fail("Invalid <window-id> 2 passed to --window-id")),

        ("h_tiles()", "echo", .fail("Argument '<string>' is mandatory")),
        ("h_tiles()", "echo --", .fail("Argument '<string>' is mandatory")),
        ("h_tiles()", "echo --foo", .fail("Unknown flag '--foo'")),
        ("h_tiles()", "echo -- %{foo}", .fail("Can't parse 'foo'.\nPossible values: \(FormatVar.unionLiteral)")),
    ] as [(String, String, CmdOutput)])
    func run(tree: String, command: String, expected: CmdOutput) async {
        setUpTree(tree)
        expectEqual(await runCmd(command), expected)
    }
}
