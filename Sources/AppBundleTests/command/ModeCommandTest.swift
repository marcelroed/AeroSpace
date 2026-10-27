@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct ModeCommandTest {
    @Test
    func testParse() {
        testParseSingleCommandSucc("mode main", ModeCommand(targetMode: "main"))
        #expect(parseCommand("mode").errorOrNil == "Argument '<binding-mode>' is mandatory")
    }

    @Test
    func testParseDashDash() {
        testParseSingleCommandSucc(
            "mode -- main",
            ModeCommand(targetMode: "main"),
        )
        testParseSingleCommandSucc(
            "mode -- --foo",
            ModeCommand(targetMode: "--foo"),
        )
        #expect(parseCommand("mode --").errorOrNil == "Argument '<binding-mode>' is mandatory")
    }
}
