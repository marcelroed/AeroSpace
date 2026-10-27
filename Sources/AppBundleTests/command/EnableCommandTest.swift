@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct EnableCommandTest {
    @Test
    func parse() {
        testParseSingleCommandSucc("enable on", EnableCmdArgs(rawArgs: [], targetState: .on))
        testParseSingleCommandSucc("enable off", EnableCmdArgs(rawArgs: [], targetState: .off))
        testParseSingleCommandSucc("enable toggle", EnableCmdArgs(rawArgs: [], targetState: .toggle))
        testParseSingleCommandSucc("enable --fail-if-noop on", EnableCmdArgs(rawArgs: [], targetState: .on).copy(\.failIfNoop, true))
    }

    @Test(arguments: [
        ("enable toggle --fail-if-noop", "ERROR: --fail-if-noop is incompatible with 'toggle' argument"),
        ("enable foo", "ERROR: Can't parse 'foo'.\n       Possible values: (on|off|toggle)"),
        ("enable", "ERROR: Argument '(on|off|toggle)' is mandatory"),
    ])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        #expect(output == .fail(error))
    }

    @Test(arguments: [
        (true, "enable on", CmdOutput(stderr: ["Already enabled. Tip: use --fail-if-noop to exit with non-zero code"])),
        (true, "enable on --fail-if-noop", .fail()),
        (false, "enable off", CmdOutput(stderr: ["Already disabled. Tip: use --fail-if-noop to exit with non-zero code"])),
        (false, "enable off --fail-if-noop", .fail()),
    ])
    func noop(isEnabled: Bool, command: String, expected: CmdOutput) async {
        TrayMenuModel.shared.isEnabled = isEnabled
        let output = await runCmd(command)
        #expect(output == expected)
        #expect(TrayMenuModel.shared.isEnabled == isEnabled)
    }

    @Test
    func toggle() async {
        var output = await runCmd("enable toggle")
        #expect(output == .ok)
        #expect(!TrayMenuModel.shared.isEnabled)
        #expect(activeMode == nil)

        output = await runCmd("enable toggle")
        #expect(output == .ok)
        #expect(TrayMenuModel.shared.isEnabled)
        #expect(activeMode == mainModeId)
    }
}
