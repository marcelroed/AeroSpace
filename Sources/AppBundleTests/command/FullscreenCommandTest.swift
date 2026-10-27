@testable import AppBundle
import Common
import Testing

/// `fullscreen`, and the commands that change a window's macOS state: `macos-native-fullscreen` and `macos-native-minimize`
@Suite(.aeroSpaceGlobalState)
struct FullscreenCommandTest {
    @Test(arguments: [
        ("fullscreen off --no-outer-gaps", "--no-outer-gaps is incompatible with 'off' argument"),
        ("fullscreen --fail-if-noop", "--fail-if-noop requires 'on' or 'off' argument"),
        ("fullscreen foo", "Can't parse 'foo'.\nPossible values: (on|off)"),
        ("macos-native-fullscreen --fail-if-noop", "--fail-if-noop requires 'on' or 'off' argument"),
        ("macos-native-fullscreen foo", "Can't parse 'foo'.\nPossible values: (on|off)"),
    ] as [(String, String)])
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

    @Test(arguments: ["fullscreen", "macos-native-fullscreen"], [
        (false, "off", CmdOutput(stderr: ["Already not fullscreen. Tip: use --fail-if-noop to exit with non-zero code"])),
        (false, "off --fail-if-noop", .fail()),
        (true, "on", CmdOutput(stderr: ["Already fullscreen. Tip: use --fail-if-noop to exit with non-zero code"])),
        (true, "on --fail-if-noop", .fail()),
    ] as [(Bool, String, CmdOutput)])
    func noop(command: String, row: (isFullscreen: Bool, args: String, expected: CmdOutput)) async {
        setUpTree("h_tiles(*1)")
        let isFullscreen: ReferenceWritableKeyPath<Window, Bool> = command == "fullscreen" ? \.isFullscreen : \.isMacosFullscreenForTest
        testWindow(1)[keyPath: isFullscreen] = row.isFullscreen
        let output = await runCmd("\(command) \(row.args)")
        expectEqual(output, row.expected)
        expectEqual(testWindow(1)[keyPath: isFullscreen], row.isFullscreen)
    }

    /// On moves the window to the fullscreen windows of its workspace. Off moves it back to the kind of container that it
    /// was in when the fullscreen began, or, if AeroSpace didn't see it begin (macOS made it fullscreen, and no refresh saw
    /// it yet), where a new window goes
    @Test(arguments: [
        ("h_tiles(*1 2)", LayoutReason.standard, "on", "h_tiles(2) macos_fullscreen(*1)"),
        ("h_tiles(*1 2)", .standard, "off", "h_tiles(2 *1)"),
        ("h_tiles(2) macos_fullscreen(*1)", .macos(prevParentKind: .floating), "off", "h_tiles(2) floating(*1)"),
    ] as [(String, LayoutReason, String, String)])
    func macosNativeFullscreen(before: String, layoutReason: LayoutReason, onOff: String, after: String) async {
        setUpTree(before)
        let window = testWindow(1)
        window.isMacosFullscreenForTest = onOff == "off" // What macOS reports before the command
        window.layoutReason = layoutReason
        expectEqual(await runCmd("macos-native-fullscreen \(onOff)"), .ok)
        expectEqual(fake.calls(of: .setNative), [.setNative(1, .fullscreen(onOff == "on"))])
        expectEqual(describeTree(), after)
    }

    /// On, then off: the window goes back to the kind of container that it left, also if a heavy refresh saw it fullscreen
    /// in between (RB-148: a floating window became a tile)
    @Test(arguments: [
        ("h_tiles(2) floating(*1)", false, "h_tiles(2) floating(*1)"),
        ("h_tiles(2) floating(*1)", true, "h_tiles(2) floating(*1)"),
        ("h_tiles(*1 2)", false, "h_tiles(2 *1)"),
    ] as [(String, Bool, String)])
    func macosNativeFullscreenOnThenOff(before: String, isRefreshedBetween: Bool, after: String) async {
        setUpTree(before)
        fake.focused = 1
        expectEqual(await runCmd("macos-native-fullscreen on"), .ok)
        if isRefreshedBetween { await Reconcile.heavy(.ax("test")) }
        expectEqual(await runCmd("macos-native-fullscreen off"), .ok)
        expectEqual(describeTree(), after)
    }

    /// When macOS deminimizes the window, it goes back to the kind of container that it left, also if a heavy refresh saw
    /// it minimized in between
    @Test(arguments: [false, true] as [Bool])
    func macosNativeMinimizeMovesTheWindowOutOfTheWorkspaceUntilItsDeminimized(isRefreshedBetween: Bool) async {
        setUpTree("h_tiles(2) floating(*1)")
        fake.focused = 1
        let output = await runCmd("macos-native-minimize")
        expectEqual(output, .ok)
        expectEqual(fake.calls(of: .setNative), [.setNative(1, .minimized(true))])
        #expect(testWindow(1).parent === macosMinimizedWindowsContainer)
        expectEqual(describeTree(), "h_tiles(*2)")
        fake.focused = 2
        if isRefreshedBetween { await Reconcile.heavy(.ax("test")) }

        fake.windows[1]?.isMinimized = false // The user clicks it in the Dock
        await Reconcile.heavy(.ax("test"))
        expectEqual(describeTree(), "h_tiles(*2) floating(1)")
    }

    /// An app that doesn't answer in time keeps its window: only a window that AX no longer finds is closed
    @Test(arguments: ["macos-native-fullscreen", "macos-native-minimize"])
    func aBusyAppIsNotAClosedWindow(command: String) async {
        setUpTree("h_tiles(*1)")
        fake.answers[testApp.pid] = false // The AX timeout of a busy app
        expectEqual(await runCmd(command), .fail("Window 1 didn't answer (its app is busy)"))

        fake.answers[testApp.pid] = nil
        fake.windows[1] = nil // The window closed, and no heavy refresh has seen it yet
        expectEqual(await runCmd(command), .fail("Window 1 closed"))
    }
}
