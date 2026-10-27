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

        var result = await parseCommand("macos-native-fullscreen off").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, ["Already not fullscreen. Tip: use --fail-if-noop to exit with non-zero code"])

        result = await parseCommand("macos-native-fullscreen off --fail-if-noop").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, [])

        window.isMacosFullscreenForTest = true
        result = await parseCommand("macos-native-fullscreen on").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, ["Already fullscreen. Tip: use --fail-if-noop to exit with non-zero code"])

        result = await parseCommand("macos-native-fullscreen on --fail-if-noop").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, [])
    }

    @Test
    func testNoWindowIsFocused() async {
        let result = await parseCommand("macos-native-fullscreen").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, [noWindowIsFocused])
    }
}
