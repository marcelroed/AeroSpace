@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct ModeCommandTest: AeroSpaceTestSuite {
    @Test
    func testParse() {
        testParseSingleCommandSucc("mode main", ModeCommand(targetMode: "main"))
        assertEquals(parseCommand("mode").errorOrNil, "Argument '<binding-mode>' is mandatory")
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
        assertEquals(parseCommand("mode --").errorOrNil, "Argument '<binding-mode>' is mandatory")
    }
}
