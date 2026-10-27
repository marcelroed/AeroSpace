@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct MacosNativeFullscreenCommandTest {
    @Test(arguments: [
        ("macos-native-fullscreen --fail-if-noop", "ERROR: --fail-if-noop requires 'on' or 'off' argument"),
        ("macos-native-fullscreen foo", "ERROR: Can't parse 'foo'. Possible values: on|off"),
    ])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        #expect(output == .fail(error))
    }

    @Test(arguments: [
        (false, "macos-native-fullscreen off", CmdOutput(stderr: ["Already not fullscreen. Tip: use --fail-if-noop to exit with non-zero code"])),
        (false, "macos-native-fullscreen off --fail-if-noop", .fail()),
        (true, "macos-native-fullscreen on", CmdOutput(stderr: ["Already fullscreen. Tip: use --fail-if-noop to exit with non-zero code"])),
        (true, "macos-native-fullscreen on --fail-if-noop", .fail()),
    ])
    func noop(isFullscreen: Bool, command: String, expected: CmdOutput) async {
        setUpTree("h_tiles(*1)")
        testWindow(1).isMacosFullscreenForTest = isFullscreen
        let output = await runCmd(command)
        #expect(output == expected)
    }

    @Test
    func noWindowIsFocused() async {
        let output = await runCmd("macos-native-fullscreen")
        #expect(output == .fail("No window is focused"))
    }
}
