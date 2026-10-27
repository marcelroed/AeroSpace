@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct TrueCommandTest {
    @Test
    func parse() {
        testParseSingleCommandSucc("true", TrueCommand())
        testParseCommandHelp("true -h")
        testParseCommandHelp("true --help")
    }

    @Test(arguments: [
        ("true", CmdOutput.ok),
        ("true foo", .fail("Unknown argument 'foo'")),
    ])
    func run(command: String, expected: CmdOutput) async {
        let output = await runCmd(command)
        #expect(output == expected)
    }
}
