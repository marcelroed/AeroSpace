@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct FalseCommandTest: AeroSpaceTestSuite {
    @Test
    func testParse() {
        testParseSingleCommandSucc("false", FalseCmdArgs(rawArgs: []))
        testParseCommandFail("false foo", msg: "ERROR: Unknown argument 'foo'")

        testParseCommandHelp("false -h")
        testParseCommandHelp("false --help")
    }

    @Test
    func testExitCode() async {
        assertEquals(await parseCommand("false").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 1)
    }
}
