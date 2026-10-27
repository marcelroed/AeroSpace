@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct ModeCommandTest {
    @Test
    func testParse() {
        testParseSingleCommandSucc("mode main", ModeCommand(targetMode: "main"))
        expectEqual(parseCommand("mode").errorOrNil, "Argument '<binding-mode>' is mandatory")
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
        expectEqual(parseCommand("mode --").errorOrNil, "Argument '<binding-mode>' is mandatory")
    }

    @Test
    func onModeChangedThatChangesTheModeBackAndForthStops() async { // RB-120
        world.config.onModeChanged = parseCommand("mode a; mode b").cmdOrDie

        let output = await runCmd("mode a")
        expectEqual(output, .ok) // The callback's error goes nowhere, like every error of a callback
        expectEqual(world.activeMode, "b") // The callback of `mode b` 32 levels deep fails
    }
}
