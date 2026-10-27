@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct FullscreenCommandTest: AeroSpaceTestSuite {
    @Test
    func testParse() {
        assertEquals(parseCommand("fullscreen off --no-outer-gaps").errorOrNil, "--no-outer-gaps is incompatible with 'off' argument")
        assertEquals(parseCommand("fullscreen --fail-if-noop").errorOrNil, "--fail-if-noop requires 'on' or 'off' argument")
        assertEquals(parseCommand("fullscreen foo").errorOrNil, "ERROR: Can't parse 'foo'. Possible values: on|off")
    }

    @Test
    func testToggle() async {
        let window = TestWindow.new(id: 1, parent: Workspace.get(byName: name).rootTilingContainer)
        assertTrue(window.focusWindow())

        await assertRun("fullscreen", exitCode: 0, stderr: [])
        assertTrue(window.isFullscreen)
        assertFalse(window.noOuterGapsInFullscreen)

        await assertRun("fullscreen", exitCode: 0)
        assertFalse(window.isFullscreen)

        await assertRun("fullscreen on --no-outer-gaps", exitCode: 0)
        assertTrue(window.isFullscreen)
        assertTrue(window.noOuterGapsInFullscreen)
    }

    @Test
    func testNoop() async {
        let window = TestWindow.new(id: 1, parent: Workspace.get(byName: name).rootTilingContainer)
        assertTrue(window.focusWindow())

        await assertRun("fullscreen off", exitCode: 0, stderr: ["Already not fullscreen. Tip: use --fail-if-noop to exit with non-zero code"])

        await assertRun("fullscreen off --fail-if-noop", exitCode: 2, stderr: [])

        window.isFullscreen = true
        await assertRun("fullscreen on", exitCode: 0, stderr: ["Already fullscreen. Tip: use --fail-if-noop to exit with non-zero code"])

        await assertRun("fullscreen on --fail-if-noop", exitCode: 2, stderr: [])
        assertTrue(window.isFullscreen)
    }

    @Test
    func testNoWindowIsFocused() async {
        await assertRun("fullscreen", exitCode: 2, stderr: [noWindowIsFocused])
    }
}
