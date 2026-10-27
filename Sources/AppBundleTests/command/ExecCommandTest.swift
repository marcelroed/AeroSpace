@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct ExecCommandTest: AeroSpaceTestSuite {
    @Test
    func testParseExecCommand() {
        testParseSingleCommandSucc("exec-and-forget echo 'foo'", ExecAndForgetCommand(bashScript: " echo 'foo'"))
    }

    @Test
    func testDescriptionReproducesTheConfiguredText() {
        // The script keeps the space after the command name, and the description used to add another one (RB-15)
        for raw in ["exec-and-forget echo 'foo'", "exec-and-forget\techo foo", "exec-and-forget\necho foo\n", "exec-and-forget"] {
            assertEquals(parseCommand(raw).cmdOrDie.shellOfCommandsDescription, raw)
        }
    }

    @Test
    func testParseScriptAfterAnyWhitespace() {
        assertEquals(parseBashScript("exec-and-forget\techo foo"), "\techo foo")
        assertEquals(parseBashScript("exec-and-forget\necho foo\n"), "\necho foo\n")
        assertEquals(parseBashScript("exec-and-forget"), "")
    }

    @Test
    func testParseRequiresWhitespaceAfterCommandName() {
        // `exec-and-forgetfoo` used to parse as `exec-and-forget foo` (RB-15)
        testParseCommandFail("exec-and-forgetfoo", msg: "Unrecognized subcommand 'exec-and-forgetfoo'")
    }
}

private func parseBashScript(_ raw: String) -> String? {
    parsedCmd(raw, as: ExecAndForgetCommand.self)?.bashScript
}
