@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct MacosNativeFullscreenCommandTest: AeroSpaceTestSuite {
    @Test
    func testParse() {
        assertEquals(parseCommand("macos-native-fullscreen --fail-if-noop").errorOrNil, "ERROR: --fail-if-noop requires 'on' or 'off' argument")
        assertEquals(parseCommand("macos-native-fullscreen foo").errorOrNil, "ERROR: Can't parse 'foo'. Possible values: on|off")
    }

    @Test
    func testNoop() async {
        let window = TestWindow.new(id: 1, parent: Workspace.get(byName: name).rootTilingContainer)
        assertTrue(window.focusWindow())

        await assertRun("macos-native-fullscreen off", exitCode: 0, stderr: ["Already not fullscreen. Tip: use --fail-if-noop to exit with non-zero code"])

        await assertRun("macos-native-fullscreen off --fail-if-noop", exitCode: 2, stderr: [])

        window.isMacosFullscreenForTest = true
        await assertRun("macos-native-fullscreen on", exitCode: 0, stderr: ["Already fullscreen. Tip: use --fail-if-noop to exit with non-zero code"])

        await assertRun("macos-native-fullscreen on --fail-if-noop", exitCode: 2, stderr: [])
    }

    @Test
    func testNoWindowIsFocused() async {
        await assertRun("macos-native-fullscreen", exitCode: 2, stderr: [noWindowIsFocused])
    }
}
