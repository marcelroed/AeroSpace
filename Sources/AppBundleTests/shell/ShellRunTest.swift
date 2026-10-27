@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct ShellRunTest: AeroSpaceTestSuite {
    @Test
    func testOrFirstSucceeds_shortCircuits() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())

        let output = await runCmd("true || workspace b")
        #expect(output == .ok)
        #expect(focus.workspace.name == "a")
    }

    @Test
    func testOrFirstFails_runsNext() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())

        let output = await runCmd("false || workspace b")
        #expect(output == .ok)
        #expect(focus.workspace.name == "b")
    }

    @Test
    func testOrAllFail_returnsLastExitCode() async {
        let output = await runCmd("false || false || false")
        #expect(output == CmdOutput(exitCode: 1))
    }

    @Test
    func testOrChainStopsOnFirstSuccess() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())

        let output = await runCmd("false || workspace b || workspace c")
        #expect(output == .ok)
        #expect(focus.workspace.name == "b")
    }

    @Test
    func testAndFirstFails_shortCircuits() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())

        let output = await runCmd("false && workspace b")
        #expect(output == CmdOutput(exitCode: 1))
        #expect(focus.workspace.name == "a")
    }

    @Test
    func testAndAllSucceed_returnsZero() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())

        let output = await runCmd("true && workspace b")
        #expect(output == .ok)
        #expect(focus.workspace.name == "b")
    }

    @Test
    func testAndChainStopsOnFirstFailure() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())

        let output = await runCmd("workspace b && false && workspace c")
        #expect(output == CmdOutput(exitCode: 1))
        #expect(focus.workspace.name == "b")
    }

    @Test
    func testAndReturnsLastSuccessExitCode() async {
        let output = await runCmd("true && true && true")
        #expect(output == .ok)
    }

    @Test
    func testSeqRunsAllRegardlessOfExitCode() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())

        let output = await runCmd("false; workspace b")
        #expect(output == .ok)
        #expect(focus.workspace.name == "b")
    }

    @Test
    func testSeqReturnsLastCommandExitCode() async {
        var output = await runCmd("true; false")
        #expect(output == CmdOutput(exitCode: 1))

        output = await runCmd("false; true")
        #expect(output == .ok)
    }

    @Test
    func testSeqConcatenatesStdout() async {
        let output = await runCmd("echo -- foo; echo -- bar; echo -- baz")
        #expect(output == CmdOutput(stdout: ["foo", "bar", "baz"]))
    }

    @Test
    func testPipeForwardsStdoutAsStdin() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())

        let output = await runCmd("echo -- a b c | workspace --stdin next")
        #expect(output == .ok)
        #expect(focus.workspace.name == "b")
    }

    @Test
    func testPipeReturnsOnlyLastStdout() async {
        let output = await runCmd("echo -- foo | echo -- bar")
        #expect(output == CmdOutput(stdout: ["bar"]))
    }

    @Test
    func testPipeForwardsIntermediateStderr() async {
        let output = await runCmd("echo --stderr -- err1 | echo -- out2")
        #expect(output == CmdOutput(stdout: ["out2"], stderr: ["err1"]))
    }

    @Test
    func testPipePipefailReturnsRightmostNonZero() async {
        var output = await runCmd("false | true")
        #expect(output == CmdOutput(exitCode: 1))

        output = await runCmd("true | false")
        #expect(output == CmdOutput(exitCode: 1))

        output = await runCmd("true | true")
        #expect(output == .ok)
    }

    @Test
    func testPipeForwardsOriginalStdin() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())

        let output = await runCmd("workspace --stdin next | echo -- done", stdin: "a\nb\nc\n")
        #expect(output == CmdOutput(stdout: ["done"]))
        #expect(focus.workspace.name == "b")
    }
}
