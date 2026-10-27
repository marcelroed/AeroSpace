@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct EnableCommandTest {
    @Test
    func parse() {
        testParseSingleCommandSucc("enable on", EnableCommand(targetState: .on))
        testParseSingleCommandSucc("enable off", EnableCommand(targetState: .off))
        testParseSingleCommandSucc("enable toggle", EnableCommand(targetState: .toggle))
        testParseSingleCommandSucc("enable --fail-if-noop on", EnableCommand(targetState: .on, failIfNoop: true))
    }

    @Test(arguments: [
        ("enable toggle --fail-if-noop", "--fail-if-noop is incompatible with 'toggle' argument"),
        ("enable foo", "Can't parse 'foo'.\nPossible values: (on|off|toggle)"),
        ("enable", "Argument '(on|off|toggle)' is mandatory"),
    ] as [(String, String)])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        expectEqual(output, .fail(error))
    }

    @Test(arguments: [
        (true, "enable on", CmdOutput(stderr: ["Already enabled. Tip: use --fail-if-noop to exit with non-zero code"])),
        (true, "enable on --fail-if-noop", .fail()),
        (false, "enable off", CmdOutput(stderr: ["Already disabled. Tip: use --fail-if-noop to exit with non-zero code"])),
        (false, "enable off --fail-if-noop", .fail()),
    ] as [(Bool, String, CmdOutput)])
    func noop(isEnabled: Bool, command: String, expected: CmdOutput) async {
        TrayMenuModel.shared.isEnabled = isEnabled
        let output = await runCmd(command)
        expectEqual(output, expected)
        expectEqual(TrayMenuModel.shared.isEnabled, isEnabled)
    }

    @Test
    func toggle() async {
        var output = await runCmd("enable toggle")
        expectEqual(output, .ok)
        #expect(!TrayMenuModel.shared.isEnabled)
        expectEqual(world.activeMode, nil)

        output = await runCmd("enable toggle")
        expectEqual(output, .ok)
        #expect(TrayMenuModel.shared.isEnabled)
        expectEqual(world.activeMode, mainModeId)
    }
}
