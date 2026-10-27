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

@Suite(.aeroSpaceGlobalState)
struct FocusCommandTest {
    @Test
    func parse() {
        testParseSingleCommandSucc("focus --boundaries workspace left", FocusCommand(target: .direction(.left)))
        testParseSingleCommandSucc(
            "focus --boundaries-action wrap-around-the-workspace dfs-prev",
            FocusCommand(target: .dfsRelative(.dfsPrev, atEdge: .wrapAroundTheWorkspace)),
        )

        expectEqual(parseCommand("focus --fail-if-fullscreen --fail-if-macos-native-fullscreen left").errorOrNil, nil)
        expectEqual(parseCommand("focus --boundaries left").errorOrNil?.contains("Possible values"), true)
    }

    @Test(arguments: [
        ("focus --boundaries workspace --boundaries workspace left", "Duplicated option '--boundaries'"),
        ("focus --window-id 42 --ignore-floating", "--window-id is incompatible with other options"),
        ("focus --boundaries all-monitors-outer-frame dfs-next", "(dfs-next|dfs-prev) only supports --boundaries workspace"),
        ("focus --window-id 42 --wrap-around", "--window-id is incompatible with other options"),
        ("focus left --boundaries-action wrap-around-the-workspace --wrap-around", "Conflicting options: --boundaries-action, --wrap-around"),
        ("focus dfs-next --fail-if-fullscreen", "--fail-if-fullscreen/--fail-if-macos-native-fullscreen require using (left|down|up|right) argument"),
        ("focus --fail-if-macos-native-fullscreen --window-id 42", "--window-id is incompatible with other options"),
        ("focus --boundaries", "'--boundaries' must be followed by '<boundary>'"),
        ("focus --boundaries-action", "'--boundaries-action' must be followed by '<action>'"),
        ("focus --boundaries-action foo left", "Can't parse 'foo'.\nPossible values: (stop|fail|wrap-around-the-workspace|wrap-around-all-monitors)"),
        ("focus foo", "Can't parse 'foo'.\nPossible values: (left|down|up|right|dfs-next|dfs-prev)"),
        ("focus --boundaries-action wrap-around-all-monitors dfs-next", "workspace and wrap-around-all-monitors is an invalid combination of values"),
        ("focus --dfs-index 0 left", "--dfs-index is incompatible with other options"),
        // An option is rejected even when it is given with its default value
        ("focus --window-id 42 --boundaries workspace", "--window-id is incompatible with other options"),
        ("focus --dfs-index 0 --boundaries-action stop", "--dfs-index is incompatible with other options"),
    ] as [(String, String)])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        expectEqual(output, .fail(error))
    }

    /// The target's errors come before the boundaries' errors, which come before the errors of the target's options
    @Test(arguments: [
        ("focus --boundaries-action wrap-around-all-monitors", "Mandatory argument is missing. (left|down|up|right|dfs-next|dfs-prev), --window-id or --dfs-index is required"),
        ("focus left --window-id 1 --boundaries-action wrap-around-all-monitors", "--window-id is incompatible with other options"),
        ("focus --window-id 1 --boundaries-action wrap-around-all-monitors", "workspace and wrap-around-all-monitors is an invalid combination of values"),
        ("focus dfs-next --fail-if-fullscreen --boundaries-action wrap-around-all-monitors", "workspace and wrap-around-all-monitors is an invalid combination of values"),
    ] as [(String, String)])
    func parseErrorOrder(command: String, error: String) async {
        let output = await runCmd(command)
        expectEqual(output, .fail(error))
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
    ] as [(String, String, String)])
    func succeeds(before: String, command: String, after: String) async {
        setUpTree(before)
        let output = await runCmd(command)
        expectEqual(output, .ok)
        expectEqual(describeTree(), after)
    }

    @Test(arguments: [
        ("h_tiles(*1 2)", "focus --boundaries-action fail dfs-prev", .fail()),
        ("h_tiles(1 *2)", "focus --boundaries-action fail dfs-next", .fail()),
        ("h_tiles(*1 2)", "focus --boundaries all-monitors-outer-frame --boundaries-action fail left", .fail()),
        ("h_tiles()", "focus --boundaries workspace --boundaries-action wrap-around-the-workspace left", .fail("No window is focused")),
        ("h_tiles()", "focus --boundaries all-monitors-outer-frame --boundaries-action wrap-around-the-workspace left", .fail("No window is focused")),
        ("h_tiles()", "focus dfs-next", .fail("No window is focused")),
        ("h_tiles(1) floating(*2)", "focus --ignore-floating dfs-prev", .fail("The window isn't part of the workspace tree")),
    ] as [(String, String, CmdOutput)])
    func fails(tree: String, command: String, expected: CmdOutput) async {
        setUpTree(tree)
        let output = await runCmd(command)
        expectEqual(output, expected)
        expectEqual(describeTree(), tree)
    }

    @Test
    func failIfFullscreen() async {
        setUpTree("h_tiles(*1 2)")
        testWindow(1).isFullscreen = true
        let output = await runCmd("focus --fail-if-fullscreen right")
        expectEqual(output, .fail())
        expectEqual(describeTree(), "h_tiles(*1 2)")
    }

    @Test
    func failIfMacosNativeFullscreen() async {
        setUpTree("h_tiles(*1 2)")
        testWindow(1).isMacosFullscreenForTest = true
        let output = await runCmd("focus --fail-if-macos-native-fullscreen right")
        expectEqual(output, .fail())
        expectEqual(describeTree(), "h_tiles(*1 2)")
    }

    @Test
    func focusOverFloatingWindows() async {
        let workspace = setUpTree("h_tiles() floating(1 *2 3)")
        for id: UInt32 in 1 ... 3 {
            let offset = CGFloat(id - 1) * 10
            testWindow(id).rect = rect(offset, offset, 100, 100)
        }
        let output = await runCmd("focus right")
        expectEqual(output, .ok)
        // Focus sees the floating windows as tiling windows only while it decides. They keep their order and MRU order
        let tree: String = "h_tiles() floating(1 2 *3)"
        expectEqual(describeTree(), tree)
        let mru: String = "floating(*3 2 1) h_tiles()"
        expectEqual(describeNode(workspace, mru: true), mru)
    }

    @Test
    func focusOverFloatingWindowsLeavesTheTilingMruAlone() async {
        let workspace = setUpFloatingWindowAboveTiles("h_tiles(v_tiles(1 2) 3) floating(*4)")
        let mruBefore = describeNode(workspace, mru: true)
        let output = await runCmd("focus left") // Nothing on the left
        expectEqual(output, .ok)
        expectEqual(describeNode(workspace, mru: true), mruBefore)
        let tree: String = "h_tiles(v_tiles(1 2) 3) floating(*4)"
        expectEqual(describeTree(), tree)
    }

    /// Before RS-NAV, focus focused while the floating windows were bound as tiling windows. Focusing window 4 made v_tiles
    /// the most recent child of the root, and layout let window 2 go fullscreen instead of window 3
    @Test
    func focusingAFloatingWindowKeepsTheFullscreenTilingWindow() async throws {
        let workspace = setUpFloatingWindowAboveTiles("h_tiles(v_tiles(1 2) 3) floating(4)")
        #expect(testWindow(2).focusWindow() && testWindow(3).focusWindow())
        testWindow(3).isFullscreen = true
        let output = await runCmd("focus --window-id 4")
        expectEqual(output, .ok)
        expectEqual(workspace.rootTilingContainer.mostRecentWindowRecursive?.windowId, 3)
        try await workspace.layoutWorkspace()
        let fullscreen: AxFrame = AxFrame(topLeft: CGPoint(x: 0, y: 0), size: CGSize(width: 1920, height: 1080))
        expectEqual(testWindow(3).setAxFrameHistory.last, fullscreen)
    }

    @Test
    func focusFindsTheMostRecentLeaf() async {
        setUpTree("h_tiles(*1 v_tiles(h_tiles(2 5) 3))")
        var output = await runCmd("focus right")
        expectEqual(output, .ok)
        expectEqual(describeTree(), "h_tiles(1 v_tiles(h_tiles(2 5) *3))")

        testWindow(2).markAsMostRecentChild()
        #expect(testWindow(1).focusWindow())
        output = await runCmd("focus right")
        expectEqual(output, .ok)
        expectEqual(describeTree(), "h_tiles(1 v_tiles(h_tiles(*2 5) 3))")

        testWindow(3).markAsMostRecentChild()
        testWindow(5).markAsMostRecentChild()
        #expect(testWindow(1).focusWindow())
        output = await runCmd("focus right")
        expectEqual(output, .ok)
        expectEqual(describeTree(), "h_tiles(1 v_tiles(h_tiles(*2 5) 3))")
    }

    @Test
    func focusDfsRelative() async {
        setUpTree("h_tiles(v_tiles(*1 h_tiles(2 3)) 4)")
        for (command, focused): (String, UInt32) in [
            ("dfs-next", 2), ("dfs-next", 3), ("dfs-next", 4),
            ("dfs-prev", 3), ("dfs-prev", 2), ("dfs-prev", 1),
        ] {
            let output = await runCmd("focus \(command)")
            expectEqual(output, .ok)
            expectEqual(focus.windowOrNil?.windowId, focused)
        }
    }

    @Test
    func allMonitorsOuterFrame_wrapAroundAllMonitors_acrossTheOrientation() async {
        setUpTree("h_tiles(1 *2 3)")
        testWindow(3).markAsMostRecentChild()
        // The most recent leaf of the wrapped monitor's workspace is focused
        let output = await runCmd("focus --boundaries all-monitors-outer-frame --boundaries-action wrap-around-all-monitors down")
        expectEqual(output, .ok)
        expectEqual(describeTree(), "h_tiles(1 2 *3)")
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

        var output = await runCmd("focus left")
        expectEqual(output, .ok)
        expectEqual(describeTree(), "h_tiles(1 *2) floating(3 4)")

        #expect(testWindow(4).focusWindow())
        output = await runCmd("focus left")
        expectEqual(output, .ok)
        expectEqual(describeTree(), "h_tiles(*1 2) floating(3 4)")
    }

    @Test
    func floatingAsTiling_accordion() async {
        setUpTree("h_accordion(1 2) floating(*3 4)")
        testWindow(1).rect = rect(0, 0, 1920, 1080)
        testWindow(2).rect = rect(0, 0, 1920, 1080)
        testWindow(3).rect = rect(1500, 400, 200, 200) // The center is to the right of the most recent window's center
        testWindow(4).rect = rect(100, 400, 200, 200) // The center is to the left of the most recent window's center

        var output = await runCmd("focus --ignore-floating left")
        expectEqual(output, .ok)
        expectEqual(describeTree(), "h_accordion(1 2) floating(*3 4)") // Floating windows aren't seen as tiling
        output = await runCmd("focus left")
        expectEqual(output, .ok)
        expectEqual(describeTree(), "h_accordion(1 *2) floating(3 4)")

        #expect(testWindow(4).focusWindow())
        output = await runCmd("focus right")
        expectEqual(output, .ok)
        expectEqual(describeTree(), "h_accordion(*1 2) floating(3 4)")
    }

    @Test
    func focusAcrossMonitors_noScreens_failsWithoutBugPrompt() async {
        setUpTree("h_tiles(*1 2)")
        // No screens (e.g., during display reconfiguration) is a normal state, not a bug (RB-40)
        await $noScreensForTests.withValue(true) {
            let output = await runCmd("focus --boundaries all-monitors-outer-frame left")
            expectEqual(output, .fail("Can't find monitors in direction left while there are no screens"))
        }
        expectEqual(describeTree(), "h_tiles(*1 2)")
    }
}

/// The tiles fill the 1920x1080 test monitor, and floating window 4 is above window 1: focus sees it as the first tiling
/// window of v_tiles
private func setUpFloatingWindowAboveTiles(_ spec: String) -> Workspace {
    let workspace = setUpTree(spec)
    let rects: [(UInt32, Rect)] = [(1, rect(0, 0, 960, 540)), (2, rect(0, 540, 960, 540)), (3, rect(960, 0, 960, 1080))]
    for (id, rect) in rects {
        testWindow(id).rect = rect
        testWindow(id).lastAppliedLayoutVirtualRect = rect
    }
    testWindow(1).parent?.lastAppliedLayoutVirtualRect = rect(0, 0, 960, 1080) // v_tiles
    testWindow(4).rect = rect(100, 100, 200, 200)
    return workspace
}
