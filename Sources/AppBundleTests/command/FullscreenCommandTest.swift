@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct FullscreenCommandTest {
    @Test(arguments: [
        ("fullscreen off --no-outer-gaps", "--no-outer-gaps is incompatible with 'off' argument"),
        ("fullscreen --fail-if-noop", "--fail-if-noop requires 'on' or 'off' argument"),
        ("fullscreen foo", "Can't parse 'foo'.\nPossible values: (on|off)"),
    ])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        expectEqual(output, .fail(error))
    }

    @Test
    func toggle() async {
        setUpTree("h_tiles(*1)")
        let window = testWindow(1)

        var output = await runCmd("fullscreen")
        expectEqual(output, .ok)
        #expect(window.isFullscreen)
        #expect(!window.noOuterGapsInFullscreen)

        output = await runCmd("fullscreen")
        expectEqual(output, .ok)
        #expect(!window.isFullscreen)

        output = await runCmd("fullscreen on --no-outer-gaps")
        expectEqual(output, .ok)
        #expect(window.isFullscreen)
        #expect(window.noOuterGapsInFullscreen)
    }

    @Test(arguments: [
        (false, "fullscreen off", CmdOutput(stderr: ["Already not fullscreen. Tip: use --fail-if-noop to exit with non-zero code"])),
        (false, "fullscreen off --fail-if-noop", .fail()),
        (true, "fullscreen on", CmdOutput(stderr: ["Already fullscreen. Tip: use --fail-if-noop to exit with non-zero code"])),
        (true, "fullscreen on --fail-if-noop", .fail()),
    ])
    func noop(isFullscreen: Bool, command: String, expected: CmdOutput) async {
        setUpTree("h_tiles(*1)")
        testWindow(1).isFullscreen = isFullscreen
        let output = await runCmd(command)
        expectEqual(output, expected)
        expectEqual(testWindow(1).isFullscreen, isFullscreen)
    }

    @Test
    func noWindowIsFocused() async {
        let output = await runCmd("fullscreen")
        expectEqual(output, .fail("No window is focused"))
    }
}
