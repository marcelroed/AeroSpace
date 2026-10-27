@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct FalseCommandTest {
    @Test
    func parse() {
        testParseSingleCommandSucc("false", FalseCmdArgs(rawArgs: []))
        testParseCommandHelp("false -h")
        testParseCommandHelp("false --help")
    }

    @Test(arguments: [
        ("false", CmdOutput(exitCode: 1)),
        ("false foo", .fail("ERROR: Unknown argument 'foo'")),
    ])
    func run(command: String, expected: CmdOutput) async {
        let output = await runCmd(command)
        #expect(output == expected)
    }
}
