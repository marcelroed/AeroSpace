@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct FalseCommandTest {
    @Test
    func parse() {
        testParseSingleCommandSucc("false", FalseCommand())
        testParseCommandHelp("false -h")
        testParseCommandHelp("false --help")
    }

    @Test(arguments: [
        ("false", CmdOutput(exitCode: 1)),
        ("false foo", .fail("Unknown argument 'foo'")),
    ])
    func run(command: String, expected: CmdOutput) async {
        let output = await runCmd(command)
        expectEqual(output, expected)
    }
}
