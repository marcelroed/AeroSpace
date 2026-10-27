@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct TrueCommandTest {
    @Test
    func parse() {
        testParseSingleCommandSucc("true", TrueCmdArgs(rawArgs: []))
        testParseCommandHelp("true -h")
        testParseCommandHelp("true --help")
    }

    @Test(arguments: [
        ("true", CmdOutput.ok),
        ("true foo", .fail("ERROR: Unknown argument 'foo'")),
    ])
    func run(command: String, expected: CmdOutput) async {
        let output = await runCmd(command)
        #expect(output == expected)
    }
}
