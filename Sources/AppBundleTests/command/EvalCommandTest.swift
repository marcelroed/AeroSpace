@testable import AppBundle
import Common
import XCTest

@MainActor
final class EvalCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        testParseSingleCommandSucc("eval 'workspace foo'", EvalCmdArgs(rawArgs: []).copy(\.shellExpr, .initialized("workspace foo")))
        assertEquals(parseCommand("eval").errorOrNil, "ERROR: Argument '<aerospace-shell-expr>' is mandatory")
    }

    func testParseDashDash() {
        testParseSingleCommandSucc(
            "eval -- '--anything'",
            EvalCmdArgs(rawArgs: []).copy(\.shellExpr, .initialized("--anything")),
        )
        assertEquals(parseCommand("eval --").errorOrNil, "ERROR: Argument '<aerospace-shell-expr>' is mandatory")
    }

    func testRunSimpleCommand() async {
        assertTrue(Workspace.get(byName: "a").focusWorkspace())

        await assertRun("eval 'workspace b'", exitCode: 0, stdout: [], stderr: [])
        assertEquals(focus.workspace.name, "b")
    }

    func testRunForwardsStdout() async {
        assertTrue(Workspace.get(byName: name).focusWorkspace())

        await assertRun("eval 'echo -- hello'", exitCode: 0, stdout: ["hello"], stderr: [])
    }

    func testRunShellComposition() async {
        assertTrue(Workspace.get(byName: "a").focusWorkspace())

        await assertRun("eval 'workspace a && workspace b'", exitCode: 0)
        assertEquals(focus.workspace.name, "b")
    }

    func testRunEmptyShellExpr() async {
        assertTrue(Workspace.get(byName: name).focusWorkspace())

        await assertRun("eval ''", exitCode: 0, stdout: [], stderr: [])
    }

    func testRunUnrecognizedSubcommand() async {
        assertTrue(Workspace.get(byName: name).focusWorkspace())

        await assertRun("eval 'no-such-command'", exitCode: 2, stdout: [], stderr: ["Unrecognized subcommand 'no-such-command'"])
    }

    func testRunInnerParseFailureForwardsErrorAndExitCode() async {
        assertTrue(Workspace.get(byName: name).focusWorkspace())

        await assertRun("eval 'workspace'", exitCode: 2, stdout: [], stderr: ["ERROR: Argument '(<workspace-name>|next|prev)' is mandatory"])
    }

    func testRunRejectsInnerHelp() async {
        assertTrue(Workspace.get(byName: name).focusWorkspace())

        await assertRun("eval 'workspace --help'", exitCode: 2, stdout: [], stderr: ["--help is not supported inside eval command"])
    }

    func testRunNestedEval() async {
        assertTrue(Workspace.get(byName: "a").focusWorkspace())

        await assertRun("eval 'eval \"workspace b\"'", exitCode: 2, stderr: ["Illegal eval (Tip: nested evals are forbidden)"])
        assertEquals(focus.workspace.name, "a")
    }
}
