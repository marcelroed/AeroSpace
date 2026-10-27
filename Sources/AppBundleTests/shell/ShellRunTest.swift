@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct ShellRunTest {
    /// Every row starts on the empty workspace `a`. There `false` fails with exit code 1 and `close` with exit code 2, so
    /// the exit code of a row tells which command's exit code an operator returns
    @Test(arguments: [
        ("true succeeds", "true", "", .ok, "a"),
        ("false fails with 1", "false", "", CmdOutput(exitCode: 1), "a"),
        ("close fails with 2", "close", "", .fail("Empty workspace"), "a"),

        ("|| stops at the first success", "true || workspace b", "", .ok, "a"),
        ("|| runs commands until one succeeds", "false || workspace b || workspace c", "", .ok, "b"),
        ("|| returns the last exit code", "false || close", "", .fail("Empty workspace"), "a"),
        ("|| returns the last exit code, not the first", "close || false", "", CmdOutput(stderr: ["Empty workspace"], exitCode: 1), "a"),

        ("&& runs commands while they succeed", "true && workspace b", "", .ok, "b"),
        ("&& stops at the first failure and returns its exit code", "workspace b && close && workspace c", "", .fail("Empty workspace"), "b"),

        ("; runs the next command after a failure", "close; workspace b", "", CmdOutput(stderr: ["Empty workspace"]), "b"),
        ("; returns the last exit code", "close; false", "", CmdOutput(stderr: ["Empty workspace"], exitCode: 1), "a"),
        ("; concatenates the stdout", "echo -- foo; echo -- bar", "", CmdOutput(stdout: ["foo", "bar"]), "a"),

        ("| feeds the stdout to the next command's stdin", "echo -- a b c | workspace --stdin next", "", .ok, "b"),
        ("| gives the stdin to the first command", "workspace --stdin next | echo -- done", "a\nb\nc\n", CmdOutput(stdout: ["done"]), "b"),
        ("| returns only the last stdout", "echo -- foo | echo -- bar", "", CmdOutput(stdout: ["bar"]), "a"),
        ("| keeps the stderr of every command", "echo --stderr -- err1 | echo --stderr -- err2 | echo -- out", "", CmdOutput(stdout: ["out"], stderr: ["err1", "err2"]), "a"),
        ("| returns the last exit code if it isn't 0", "false | close", "", .fail("Empty workspace"), "a"),
        ("| returns the last exit code if it isn't 0, not the first", "close | false", "", CmdOutput(stderr: ["Empty workspace"], exitCode: 1), "a"),
        ("| returns the first exit code if the last is 0", "close | true", "", .fail("Empty workspace"), "a"),
    ] as [(String, String, String, CmdOutput, String)])
    func runs(label: String, command: String, stdin: String, expected: CmdOutput, workspace: String) async {
        #expect(Workspace.get(byName: "a").focusWorkspace())

        let output = await runCmd(command, stdin: stdin)
        expectEqual(output, expected, Comment(rawValue: label))
        expectEqual(focus.workspace.name, workspace, Comment(rawValue: label))
    }
}
