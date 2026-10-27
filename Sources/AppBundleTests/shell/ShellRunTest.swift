@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct ShellRunTest: AeroSpaceTestSuite {
    @Test
    func testOrFirstSucceeds_shortCircuits() async {
        assertTrue(Workspace.get(byName: "a").focusWorkspace())

        await assertRun("true || workspace b", exitCode: 0)
        assertEquals(focus.workspace.name, "a")
    }

    @Test
    func testOrFirstFails_runsNext() async {
        assertTrue(Workspace.get(byName: "a").focusWorkspace())

        await assertRun("false || workspace b", exitCode: 0)
        assertEquals(focus.workspace.name, "b")
    }

    @Test
    func testOrAllFail_returnsLastExitCode() async {
        await assertRun("false || false || false", exitCode: 1)
    }

    @Test
    func testOrChainStopsOnFirstSuccess() async {
        assertTrue(Workspace.get(byName: "a").focusWorkspace())

        await assertRun("false || workspace b || workspace c", exitCode: 0)
        assertEquals(focus.workspace.name, "b")
    }

    @Test
    func testAndFirstFails_shortCircuits() async {
        assertTrue(Workspace.get(byName: "a").focusWorkspace())

        await assertRun("false && workspace b", exitCode: 1)
        assertEquals(focus.workspace.name, "a")
    }

    @Test
    func testAndAllSucceed_returnsZero() async {
        assertTrue(Workspace.get(byName: "a").focusWorkspace())

        await assertRun("true && workspace b", exitCode: 0)
        assertEquals(focus.workspace.name, "b")
    }

    @Test
    func testAndChainStopsOnFirstFailure() async {
        assertTrue(Workspace.get(byName: "a").focusWorkspace())

        await assertRun("workspace b && false && workspace c", exitCode: 1)
        assertEquals(focus.workspace.name, "b")
    }

    @Test
    func testAndReturnsLastSuccessExitCode() async {
        await assertRun("true && true && true", exitCode: 0)
    }

    @Test
    func testSeqRunsAllRegardlessOfExitCode() async {
        assertTrue(Workspace.get(byName: "a").focusWorkspace())

        await assertRun("false; workspace b", exitCode: 0)
        assertEquals(focus.workspace.name, "b")
    }

    @Test
    func testSeqReturnsLastCommandExitCode() async {
        await assertRun("true; false", exitCode: 1)

        await assertRun("false; true", exitCode: 0)
    }

    @Test
    func testSeqConcatenatesStdout() async {
        await assertRun("echo -- foo; echo -- bar; echo -- baz", exitCode: 0, stdout: ["foo", "bar", "baz"])
    }

    @Test
    func testPipeForwardsStdoutAsStdin() async {
        assertTrue(Workspace.get(byName: "a").focusWorkspace())

        await assertRun("echo -- a b c | workspace --stdin next", exitCode: 0)
        assertEquals(focus.workspace.name, "b")
    }

    @Test
    func testPipeReturnsOnlyLastStdout() async {
        await assertRun("echo -- foo | echo -- bar", exitCode: 0, stdout: ["bar"])
    }

    @Test
    func testPipeForwardsIntermediateStderr() async {
        await assertRun("echo --stderr -- err1 | echo -- out2", exitCode: 0, stdout: ["out2"], stderr: ["err1"])
    }

    @Test
    func testPipePipefailReturnsRightmostNonZero() async {
        await assertRun("false | true", exitCode: 1)

        await assertRun("true | false", exitCode: 1)

        await assertRun("true | true", exitCode: 0)
    }

    @Test
    func testPipeForwardsOriginalStdin() async {
        assertTrue(Workspace.get(byName: "a").focusWorkspace())

        await assertRun("workspace --stdin next | echo -- done", stdin: "a\nb\nc\n", exitCode: 0, stdout: ["done"])
        assertEquals(focus.workspace.name, "b")
    }
}
