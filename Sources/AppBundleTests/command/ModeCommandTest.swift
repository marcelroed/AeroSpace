@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct ModeCommandTest {
    @Test(arguments: [
        ("mode main", "main", nil),
        ("mode -- --foo", "--foo", nil),
        ("mode", nil, "Argument '<binding-mode>' is mandatory"),
        ("mode --", nil, "Argument '<binding-mode>' is mandatory"),
    ] as [(String, String?, String?)])
    func parse(args: String, targetMode: String?, error: String?) {
        expectEqual(parsedCmd(args, as: ModeCommand.self)?.targetMode, targetMode)
        expectEqual(parseCommand(args).errorOrNil, error)
    }

    @Test
    func onModeChangedThatChangesTheModeBackAndForthStops() async { // RB-120
        world.config.onModeChanged = parseCommand("mode a; mode b").cmdOrDie

        let output = await runCmd("mode a")
        expectEqual(output, .ok) // The callback's error goes nowhere, like every error of a callback
        expectEqual(world.activeMode, "b") // The callback of `mode b` 32 levels deep fails
    }
}
