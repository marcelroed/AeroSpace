@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct ShellRunTest {
    @Test
    func testOrFirstSucceeds_shortCircuits() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())

        let output = await runCmd("true || workspace b")
        expectEqual(output, .ok)
        expectEqual(focus.workspace.name, "a")
    }

    @Test
    func testOrFirstFails_runsNext() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())

        let output = await runCmd("false || workspace b")
        expectEqual(output, .ok)
        expectEqual(focus.workspace.name, "b")
    }

    @Test
    func testOrAllFail_returnsLastExitCode() async {
        let output = await runCmd("false || false || false")
        expectEqual(output, CmdOutput(exitCode: 1))
    }

    @Test
    func testOrChainStopsOnFirstSuccess() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())

        let output = await runCmd("false || workspace b || workspace c")
        expectEqual(output, .ok)
        expectEqual(focus.workspace.name, "b")
    }

    @Test
    func testAndFirstFails_shortCircuits() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())

        let output = await runCmd("false && workspace b")
        expectEqual(output, CmdOutput(exitCode: 1))
        expectEqual(focus.workspace.name, "a")
    }

    @Test
    func testAndAllSucceed_returnsZero() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())

        let output = await runCmd("true && workspace b")
        expectEqual(output, .ok)
        expectEqual(focus.workspace.name, "b")
    }

    @Test
    func testAndChainStopsOnFirstFailure() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())

        let output = await runCmd("workspace b && false && workspace c")
        expectEqual(output, CmdOutput(exitCode: 1))
        expectEqual(focus.workspace.name, "b")
    }

    @Test
    func testAndReturnsLastSuccessExitCode() async {
        let output = await runCmd("true && true && true")
        expectEqual(output, .ok)
    }

    @Test
    func testSeqRunsAllRegardlessOfExitCode() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())

        let output = await runCmd("false; workspace b")
        expectEqual(output, .ok)
        expectEqual(focus.workspace.name, "b")
    }

    @Test
    func testSeqReturnsLastCommandExitCode() async {
        var output = await runCmd("true; false")
        expectEqual(output, CmdOutput(exitCode: 1))

        output = await runCmd("false; true")
        expectEqual(output, .ok)
    }

    @Test
    func testSeqConcatenatesStdout() async {
        let output = await runCmd("echo -- foo; echo -- bar; echo -- baz")
        expectEqual(output, CmdOutput(stdout: ["foo", "bar", "baz"]))
    }

    @Test
    func testPipeForwardsStdoutAsStdin() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())

        let output = await runCmd("echo -- a b c | workspace --stdin next")
        expectEqual(output, .ok)
        expectEqual(focus.workspace.name, "b")
    }

    @Test
    func testPipeReturnsOnlyLastStdout() async {
        let output = await runCmd("echo -- foo | echo -- bar")
        expectEqual(output, CmdOutput(stdout: ["bar"]))
    }

    @Test
    func testPipeForwardsIntermediateStderr() async {
        let output = await runCmd("echo --stderr -- err1 | echo -- out2")
        expectEqual(output, CmdOutput(stdout: ["out2"], stderr: ["err1"]))
    }

    @Test
    func testPipePipefailReturnsRightmostNonZero() async {
        var output = await runCmd("false | true")
        expectEqual(output, CmdOutput(exitCode: 1))

        output = await runCmd("true | false")
        expectEqual(output, CmdOutput(exitCode: 1))

        output = await runCmd("true | true")
        expectEqual(output, .ok)

        output = await runCmd("false | true | true")
        expectEqual(output, CmdOutput(exitCode: 1))
    }

    @Test
    func testPipeOfThreeForwardsEveryStderr() async {
        let output = await runCmd("echo --stderr -- err1 | echo --stderr -- err2 | echo -- out3")
        expectEqual(output, CmdOutput(stdout: ["out3"], stderr: ["err1", "err2"]))
    }

    @Test
    func testPipeForwardsOriginalStdin() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())

        let output = await runCmd("workspace --stdin next | echo -- done", stdin: "a\nb\nc\n")
        expectEqual(output, CmdOutput(stdout: ["done"]))
        expectEqual(focus.workspace.name, "b")
    }
}
