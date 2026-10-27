@testable import AppBundle
import AppKit
import Common
import Testing

// todo write tests
//
// test 1
//     horizontal
//         window1
//         vertical
//             vertical
//                 window2 <-- focused
//             vertical
//                 window5
//                 horizontal
//                     window3
//                     window4
// pre-condition: focus_wrapping force_workspace
// action: focus up
// expected: mru(window3, window4) is focused

@MainActor
@Suite(.aeroSpaceGlobalState)
struct FocusCommandTest {
    @Test
    func parse() {
        var expected = FocusCmdArgs(rawArgs: [], cardinalOrDfsDirection: .direction(.left))
        expected.rawBoundaries = .workspace
        testParseSingleCommandSucc("focus --boundaries workspace left", expected)

        var expectedDfs = FocusCmdArgs(rawArgs: [], cardinalOrDfsDirection: .dfsRelative(.dfsPrev))
        expectedDfs.rawBoundariesAction = .wrapAroundTheWorkspace
        testParseSingleCommandSucc("focus --boundaries-action wrap-around-the-workspace dfs-prev", expectedDfs)

        #expect(parseCommand("focus --fail-if-fullscreen --fail-if-macos-native-fullscreen left").errorOrNil == nil)
        #expect(parseCommand("focus --boundaries left").errorOrNil?.contains("Possible values") == true)
    }

    @Test(arguments: [
        ("focus --boundaries workspace --boundaries workspace left", "ERROR: Duplicated option '--boundaries'"),
        ("focus --window-id 42 --ignore-floating", "ERROR: --window-id is incompatible with other options"),
        ("focus --boundaries all-monitors-outer-frame dfs-next", "ERROR: (dfs-next|dfs-prev) only supports --boundaries workspace"),
        ("focus --window-id 42 --wrap-around", "ERROR: --window-id is incompatible with other options"),
        ("focus left --boundaries-action wrap-around-the-workspace --wrap-around", "ERROR: Conflicting options: --boundaries-action, --wrap-around"),
        ("focus dfs-next --fail-if-fullscreen", "ERROR: --fail-if-fullscreen/--fail-if-macos-native-fullscreen require using (left|down|up|right) argument"),
        ("focus --fail-if-macos-native-fullscreen --window-id 42", "ERROR: --window-id is incompatible with other options"),
        ("focus --boundaries", "ERROR: <boundary> is mandatory"),
        ("focus --boundaries-action", "ERROR: <action> is mandatory"),
        ("focus --boundaries-action foo left", "ERROR: Can't parse 'foo'.\n       Possible values: (stop|fail|wrap-around-the-workspace|wrap-around-all-monitors)"),
        ("focus foo", "ERROR: Can't parse 'foo'.\n       Possible values: (left|down|up|right|dfs-next|dfs-prev)"),
        ("focus --boundaries-action wrap-around-all-monitors dfs-next", "ERROR: workspace and wrap-around-all-monitors is an invalid combination of values"),
        ("focus --dfs-index 0 left", "ERROR: --dfs-index is incompatible with other options"),
    ])
    func parseError(command: String, error: String) async {
        #expect(await runCmd(command) == .fail(error))
    }

    @Test(arguments: [
        ("h_tiles(*1 2)", "focus right", "h_tiles(1 *2)"),
        ("h_tiles(*1 2)", "focus --fail-if-fullscreen --fail-if-macos-native-fullscreen right", "h_tiles(1 *2)"),
        // Across the orientation of the root
        ("h_tiles(1 *2)", "focus up", "h_tiles(1 *2)"),
        ("h_tiles(1 *2)", "focus down", "h_tiles(1 *2)"),
        // No wrapping by default
        ("h_tiles(*1 2)", "focus left", "h_tiles(*1 2)"),
        ("h_tiles(*1 2)", "focus --boundaries workspace --boundaries-action wrap-around-the-workspace left", "h_tiles(1 *2)"),
        // Out of the container
        ("h_tiles(1 v_tiles(*2))", "focus left", "h_tiles(*1 v_tiles(2))"),
        ("h_tiles(1 h_tiles(*2))", "focus left", "h_tiles(*1 h_tiles(2))"),
        ("h_tiles(*1 2)", "focus --boundaries-action stop dfs-prev", "h_tiles(*1 2)"),
        ("h_tiles(*1 2)", "focus --boundaries-action wrap-around-the-workspace dfs-prev", "h_tiles(1 *2)"),
        ("h_tiles(1 *2)", "focus --boundaries-action stop dfs-next", "h_tiles(1 *2)"),
        ("h_tiles(1 *2)", "focus --boundaries-action wrap-around-the-workspace dfs-next", "h_tiles(*1 2)"),
        // The test monitor is the only monitor, so the monitor in the direction wraps around to the same monitor
        ("h_tiles(*1 2)", "focus --boundaries all-monitors-outer-frame --boundaries-action stop left", "h_tiles(*1 2)"),
        ("h_tiles(*1 2)", "focus --boundaries all-monitors-outer-frame --boundaries-action wrap-around-the-workspace left", "h_tiles(1 *2)"),
        // Along the orientation, the leaf snapped to the opposite side is focused
        ("h_tiles(1 2 *3)", "focus --boundaries all-monitors-outer-frame --boundaries-action wrap-around-all-monitors right", "h_tiles(*1 2 3)"),
        ("h_tiles()", "focus --boundaries all-monitors-outer-frame --boundaries-action wrap-around-all-monitors left", "h_tiles()"),
    ])
    func succeeds(before: String, command: String, after: String) async {
        setUpTree(before)
        #expect(await runCmd(command) == .ok)
        #expect(describeTree() == after)
    }

    @Test(arguments: [
        ("h_tiles(*1 2)", "focus --boundaries-action fail dfs-prev", CmdOutput.fail()),
        ("h_tiles(1 *2)", "focus --boundaries-action fail dfs-next", .fail()),
        ("h_tiles(*1 2)", "focus --boundaries all-monitors-outer-frame --boundaries-action fail left", .fail()),
        ("h_tiles()", "focus --boundaries workspace --boundaries-action wrap-around-the-workspace left", .fail("No window is focused")),
        ("h_tiles()", "focus --boundaries all-monitors-outer-frame --boundaries-action wrap-around-the-workspace left", .fail("No window is focused")),
        ("h_tiles()", "focus dfs-next", .fail("No window is focused")),
        ("h_tiles(1) floating(*2)", "focus --ignore-floating dfs-prev", .fail("The window isn't part of the workspace tree")),
    ])
    func fails(tree: String, command: String, output: CmdOutput) async {
        setUpTree(tree)
        #expect(await runCmd(command) == output)
        #expect(describeTree() == tree)
    }

    @Test
    func failIfFullscreen() async {
        setUpTree("h_tiles(*1 2)")
        testWindow(1).isFullscreen = true
        #expect(await runCmd("focus --fail-if-fullscreen right").exitCode == 2)
        #expect(describeTree() == "h_tiles(*1 2)")
    }

    @Test
    func failIfMacosNativeFullscreen() async {
        setUpTree("h_tiles(*1 2)")
        testWindow(1).isMacosFullscreenForTest = true
        #expect(await runCmd("focus --fail-if-macos-native-fullscreen right").exitCode == 2)
        #expect(describeTree() == "h_tiles(*1 2)")
    }

    @Test
    func focusOverFloatingWindows() async {
        setUpTree("h_tiles() floating(1 *2 3)")
        for id: UInt32 in 1 ... 3 {
            testWindow(id).rect = rect(CGFloat(id - 1) * 10, CGFloat(id - 1) * 10, 100, 100)
        }
        #expect(await runCmd("focus right") == .ok)
        // Not describeTree(): focus reorders the floating windows by their centers, from right to left (suspected bug)
        #expect(focus.windowOrNil?.windowId == 3)
    }

    @Test
    func focusFindsTheMostRecentLeaf() async {
        setUpTree("h_tiles(*1 v_tiles(h_tiles(2 5) 3))")
        #expect(await runCmd("focus right") == .ok)
        #expect(describeTree() == "h_tiles(1 v_tiles(h_tiles(2 5) *3))")

        testWindow(2).markAsMostRecentChild()
        #expect(testWindow(1).focusWindow())
        #expect(await runCmd("focus right") == .ok)
        #expect(describeTree() == "h_tiles(1 v_tiles(h_tiles(*2 5) 3))")

        testWindow(3).markAsMostRecentChild()
        testWindow(5).markAsMostRecentChild()
        #expect(testWindow(1).focusWindow())
        #expect(await runCmd("focus right") == .ok)
        #expect(describeTree() == "h_tiles(1 v_tiles(h_tiles(*2 5) 3))")
    }

    @Test
    func focusDfsRelative() async {
        setUpTree("h_tiles(v_tiles(*1 h_tiles(2 3)) 4)")
        for (command, focused): (String, UInt32) in [
            ("dfs-next", 2), ("dfs-next", 3), ("dfs-next", 4),
            ("dfs-prev", 3), ("dfs-prev", 2), ("dfs-prev", 1),
        ] {
            #expect(await runCmd("focus \(command)") == .ok)
            #expect(focus.windowOrNil?.windowId == focused)
        }
    }

    @Test
    func allMonitorsOuterFrame_wrapAroundAllMonitors_acrossTheOrientation() async {
        setUpTree("h_tiles(1 *2 3)")
        testWindow(3).markAsMostRecentChild()
        // The most recent leaf of the wrapped monitor's workspace is focused
        #expect(await runCmd("focus --boundaries all-monitors-outer-frame --boundaries-action wrap-around-all-monitors down") == .ok)
        #expect(describeTree() == "h_tiles(1 2 *3)")
    }

    // Floating windows are seen as tiling windows next to the tiling window under their center
    @Test
    func floatingAsTiling_tiles() async {
        setUpTree("h_tiles(1 2) floating(*3 4)")
        for (id, x): (UInt32, CGFloat) in [(1, 0), (2, 960)] {
            testWindow(id).rect = rect(x, 0, 960, 1080)
            testWindow(id).lastAppliedLayoutVirtualRect = rect(x, 0, 960, 1080)
        }
        testWindow(3).rect = rect(1400, 400, 200, 200) // The center is to the right of window 2's center
        testWindow(4).rect = rect(1200, 400, 200, 200) // The center is to the left of window 2's center

        #expect(await runCmd("focus left") == .ok)
        #expect(describeTree() == "h_tiles(1 *2) floating(3 4)")

        #expect(testWindow(4).focusWindow())
        #expect(await runCmd("focus left") == .ok)
        #expect(describeTree() == "h_tiles(*1 2) floating(3 4)")
    }

    @Test
    func floatingAsTiling_accordion() async {
        setUpTree("h_accordion(1 2) floating(*3 4)")
        testWindow(1).rect = rect(0, 0, 1920, 1080)
        testWindow(2).rect = rect(0, 0, 1920, 1080)
        testWindow(3).rect = rect(1500, 400, 200, 200) // The center is to the right of the most recent window's center
        testWindow(4).rect = rect(100, 400, 200, 200) // The center is to the left of the most recent window's center

        #expect(await runCmd("focus --ignore-floating left") == .ok)
        #expect(describeTree() == "h_accordion(1 2) floating(*3 4)") // Floating windows aren't seen as tiling
        #expect(await runCmd("focus left") == .ok)
        #expect(describeTree() == "h_accordion(1 *2) floating(3 4)")

        #expect(testWindow(4).focusWindow())
        #expect(await runCmd("focus right") == .ok)
        #expect(describeTree() == "h_accordion(*1 2) floating(3 4)")
    }

    @Test
    func focusAcrossMonitors_noScreens_failsWithoutBugPrompt() async {
        setUpTree("h_tiles(*1 2)")
        // No screens (e.g., during display reconfiguration) is a normal state, not a bug (RB-40)
        await $noScreensForTests.withValue(true) {
            #expect(await runCmd("focus --boundaries all-monitors-outer-frame left") == .fail("Can't focus across monitors while there are no screens"))
        }
        #expect(describeTree() == "h_tiles(*1 2)")
    }
}
