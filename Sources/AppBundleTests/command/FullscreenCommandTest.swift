@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct FullscreenCommandTest: AeroSpaceTestSuite {
    @Test
    func testParse() {
        assertEquals(parseCommand("fullscreen off --no-outer-gaps").errorOrNil, "ERROR: --no-outer-gaps is incompatible with 'off' argument")
        assertEquals(parseCommand("fullscreen --fail-if-noop").errorOrNil, "ERROR: --fail-if-noop requires 'on' or 'off' argument")
        assertEquals(parseCommand("fullscreen foo").errorOrNil, "ERROR: Can't parse 'foo'. Possible values: on|off")
    }

    @Test
    func testToggle() async {
        let window = TestWindow.new(id: 1, parent: Workspace.get(byName: name).rootTilingContainer)
        assertTrue(window.focusWindow())

        var result = await parseCommand("fullscreen").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, [])
        assertTrue(window.isFullscreen)
        assertFalse(window.noOuterGapsInFullscreen)

        result = await parseCommand("fullscreen").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertFalse(window.isFullscreen)

        result = await parseCommand("fullscreen on --no-outer-gaps").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertTrue(window.isFullscreen)
        assertTrue(window.noOuterGapsInFullscreen)
    }

    @Test
    func testNoop() async {
        let window = TestWindow.new(id: 1, parent: Workspace.get(byName: name).rootTilingContainer)
        assertTrue(window.focusWindow())

        var result = await parseCommand("fullscreen off").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, ["Already not fullscreen. Tip: use --fail-if-noop to exit with non-zero code"])

        result = await parseCommand("fullscreen off --fail-if-noop").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, [])

        window.isFullscreen = true
        result = await parseCommand("fullscreen on").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, ["Already fullscreen. Tip: use --fail-if-noop to exit with non-zero code"])

        result = await parseCommand("fullscreen on --fail-if-noop").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, [])
        assertTrue(window.isFullscreen)
    }

    @Test
    func testNoWindowIsFocused() async {
        let result = await parseCommand("fullscreen").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, [noWindowIsFocused])
    }
}
