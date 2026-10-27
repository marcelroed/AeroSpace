@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct TrueCommandTest: AeroSpaceTestSuite {
    @Test
    func testParse() {
        testParseSingleCommandSucc("true", TrueCmdArgs(rawArgs: []))
        testParseCommandFail("true foo", msg: "ERROR: Unknown argument \'foo\'")

        testParseCommandHelp("true -h")
        testParseCommandHelp("true --help")
    }

    @Test
    func testExitCode() async {
        await assertRun("true", exitCode: 0)
    }
}
