@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct EvalCommandTest {
    /// The command runs in the focused workspace 'a'
    @Test(arguments: [
        ("eval 'workspace b'", .ok, "b"),
        // The noop 'workspace a' succeeds, so 'workspace b' runs
        ("eval 'workspace a && workspace b'", CmdOutput(stderr: ["Workspace 'a' is already focused. Tip: use --fail-if-noop to exit with non-zero code"]), "b"),
        ("eval 'echo -- hello'", CmdOutput(stdout: ["hello"]), "a"),
        ("eval ''", .ok, "a"),
        ("eval", .fail("Argument '<aerospace-shell-expr>' is mandatory"), "a"),
        ("eval --", .fail("Argument '<aerospace-shell-expr>' is mandatory"), "a"),
        // After '--', the expression is the argument even if it looks like an option
        ("eval -- '--anything'", .fail("Unrecognized subcommand '--anything'"), "a"),
        ("eval 'no-such-command'", .fail("Unrecognized subcommand 'no-such-command'"), "a"),
        // The error and the exit code of the inner command
        ("eval 'workspace'", .fail("Argument '(<workspace-name>|next|prev)' is mandatory"), "a"),
        ("eval 'workspace --help'", .fail("--help is not supported inside eval command"), "a"),
        ("eval 'eval \"workspace b\"'", .fail("Illegal eval (Tip: nested evals are forbidden)"), "a"),
    ] as [(String, CmdOutput, String)])
    func run(command: String, expected: CmdOutput, focusedWorkspace: String) async {
        #expect(Workspace.get(byName: "a").focusWorkspace())
        let output = await runCmd(command)
        expectEqual(output, expected)
        expectEqual(focus.workspace.name, focusedWorkspace)
    }
}
