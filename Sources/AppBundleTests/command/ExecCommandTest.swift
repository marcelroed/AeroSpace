@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct ExecCommandTest: AeroSpaceTestSuite {
    @Test
    func testParseExecCommand() {
        testParseSingleCommandSucc("exec-and-forget echo 'foo'", ExecAndForgetCmdArgs(bashScript: " echo 'foo'"))
    }
}
