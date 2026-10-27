@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct EnableCommandTest {
    @Test(arguments: [
        (true, "enable on", CmdOutput(stderr: ["Already enabled. Tip: use --fail-if-noop to exit with non-zero code"])),
        (true, "enable on --fail-if-noop", .fail()),
        (false, "enable off", CmdOutput(stderr: ["Already disabled. Tip: use --fail-if-noop to exit with non-zero code"])),
        (false, "enable off --fail-if-noop", .fail()),
    ] as [(Bool, String, CmdOutput)])
    func noop(isEnabled: Bool, command: String, expected: CmdOutput) async {
        world.isEnabled = isEnabled
        let output = await runCmd(command)
        expectEqual(output, expected)
        expectEqual(world.isEnabled, isEnabled)
    }

    @Test
    func toggle() async {
        var output = await runCmd("enable toggle")
        expectEqual(output, .ok)
        #expect(!world.isEnabled)
        expectEqual(world.activeMode, nil)

        output = await runCmd("enable toggle")
        expectEqual(output, .ok)
        #expect(world.isEnabled)
        expectEqual(world.activeMode, mainModeId)
    }
}
