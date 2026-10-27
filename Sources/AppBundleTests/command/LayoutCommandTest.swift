@testable import AppBundle
import Common
import XCTest

@MainActor
final class LayoutCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        assertNil(parseCommand("layout v_tiles h_tiles").errorOrNil)
        assertNil(parseCommand("layout tiling").errorOrNil)
        assertNil(parseCommand("layout floating tiling").errorOrNil)
        assertNil(parseCommand("layout --window-id 1 horizontal vertical").errorOrNil)

        testParseCommandFail("layout --root accordion tiling", msg: "ERROR: layout command: --root and tiling|floating are incompatible")
        testParseSingleCommandSucc(
            "layout --root accordion tiles",
            LayoutCmdArgs(rawArgs: [], toggleBetween: [.accordion, .tiles]).copy(\.root, true),
        )
        testParseCommandFail("layout --workspace 2 tiles", msg: "ERROR: --workspace flag requires using an explicit --root flag")
        testParseCommandFail("layout --workspace 2 --window-id 2 tiles", msg: "ERROR: Conflicting options: --window-id, --workspace")
        testParseCommandFail("layout --fail-if-noop accordion tiling", msg: "ERROR: --fail-if-noop allows only one <target-layout> argument")

        testParseSingleCommandSucc(
            "layout --for-next-detected-window floating",
            LayoutCmdArgs(rawArgs: [], toggleBetween: [.floating]).copy(\.forNextDetectedWindow, true),
        )
        testParseCommandFail("layout --for-next-detected-window floating tiling", msg: "ERROR: " + layoutCommandForNextDetectedWindowFlagIncompatibilityMsg)
        testParseCommandFail("layout --for-next-detected-window accordion", msg: "ERROR: " + layoutCommandForNextDetectedWindowFlagIncompatibilityMsg)
        testParseCommandFail("layout --for-next-detected-window --window-id 1 floating", msg: "ERROR: Conflicting options: --for-next-detected-window, --window-id")
        testParseCommandFail("layout --for-next-detected-window --workspace 2 floating", msg: "ERROR: Conflicting options: --for-next-detected-window, --workspace")
        testParseCommandFail("layout --for-next-detected-window --root floating", msg: "ERROR: Conflicting options: --for-next-detected-window, --root")
        testParseCommandFail("layout --for-next-detected-window --fail-if-noop floating", msg: "ERROR: Conflicting options: --fail-if-noop, --for-next-detected-window")
    }

    func testForNextDetectedWindow_doesNotTouchExistingWindows() async {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        await assertRun("layout floating --for-next-detected-window", exitCode: 0)
        assertEquals(root.layoutDescription, .h_tiles([.window(1)]))
        assertEquals(workspace.floatingWindows, [])
    }

    func testForNextDetectedWindow_appliesToTheNextDetectedWindow() async {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        await parseCommand("layout floating --for-next-detected-window").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await runOnWindowDetected(ifConventional: TestWindow.new(id: 2, parent: root))

        assertEquals(workspace.floatingWindows.map(\.windowId), [2])
        assertEquals(root.layoutDescription, .h_tiles([.window(1)]))
    }

    func testForNextDetectedWindow_isConsumedOnlyOnce() async {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        await parseCommand("layout floating --for-next-detected-window").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await runOnWindowDetected(ifConventional: TestWindow.new(id: 2, parent: root))
        await runOnWindowDetected(ifConventional: TestWindow.new(id: 3, parent: root))

        assertEquals(workspace.floatingWindows.map(\.windowId), [2])
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(3)]))
    }

    func testForNextDetectedWindow_secondInvocationReplacesTheScheduledLayout() async {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        await parseCommand("layout floating --for-next-detected-window").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await parseCommand("layout tiling --for-next-detected-window").cmdOrDie.run(.defaultEnv, .emptyStdin)
        // The window is detected as floating. The replaced 'floating' would have been a noop, 'tiling' tiles it
        await runOnWindowDetected(ifConventional: TestWindow.new(id: 2, parent: workspace.floatingWindowsContainer))

        assertEquals(workspace.floatingWindows, [])
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2)]))
    }

    func testForNextDetectedWindow_appliedBeforeAndAfterOnWindowDetectedCallbacks() async {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        config.onWindowDetected = [
            WindowDetectedCallback(
                matcher: .command(.empty), // true
                run: parseCommand("layout floating tiling").cmdOrDie,
            ),
        ]

        await parseCommand("layout floating --for-next-detected-window").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await runOnWindowDetected(ifConventional: TestWindow.new(id: 2, parent: root))

        assertEquals(workspace.floatingWindows.singleOrNil()?.windowId, 2)
        assertEquals(root.layoutDescription, .h_tiles([.window(1)]))
    }

    func testChangeOrientation() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }
        assertEquals(root.orientation, .h)

        await parseCommand("layout vertical").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.orientation, .v)
        assertEquals(root.layoutDescription, .v_tiles([.window(1), .window(2)]))
    }

    func testChangeLayoutToAccordion() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }
        assertEquals(root.layout, .tiles)

        await parseCommand("layout accordion").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layout, .accordion)
        assertEquals(root.layoutDescription, .h_accordion([.window(1), .window(2)]))
    }

    func testChangeBothLayoutAndOrientation() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        await parseCommand("layout v_accordion").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layout, .accordion)
        assertEquals(root.orientation, .v)
        assertEquals(root.layoutDescription, .v_accordion([.window(1), .window(2)]))
    }

    func testToggleBetween_skipsMatching() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        await parseCommand("layout h_tiles h_accordion").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layout, .accordion)
        assertEquals(root.orientation, .h)
    }

    func testToggleBetween_allMatch_isNoop() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        await assertRun("layout h_tiles", exitCode: 0, stderr: ["Already in the requested h_tiles mode. Tip: use --fail-if-noop to exit with non-zero code"])
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2)]))
    }

    func testEmptyWorkspace_changeOrientation() async {
        let workspace = Workspace.get(byName: name)
        assertTrue(workspace.isEffectivelyEmpty)

        await assertRun("layout v_tiles", env: .defaultEnv.withWorkspaceName(name), exitCode: 0)
        assertEquals(workspace.rootTilingContainer.orientation, .v)
        assertEquals(workspace.rootTilingContainer.layout, .tiles)
    }

    func testEmptyWorkspace_changeLayout() async {
        let workspace = Workspace.get(byName: name)
        assertTrue(workspace.isEffectivelyEmpty)

        await assertRun("layout accordion", env: .defaultEnv.withWorkspaceName(name), exitCode: 0)
        assertEquals(workspace.rootTilingContainer.layout, .accordion)
        assertEquals(workspace.rootTilingContainer.orientation, .h)
    }

    func testEmptyWorkspace_alreadyMatches_isNoop() async {
        let workspace = Workspace.get(byName: name)
        assertTrue(workspace.isEffectivelyEmpty)

        await assertRun(
            "layout h_tiles",
            env: .defaultEnv.withWorkspaceName(name),
            exitCode: 0,
            stderr: ["Already in the requested h_tiles mode. Tip: use --fail-if-noop to exit with non-zero code"],
        )
        assertEquals(workspace.rootTilingContainer.layout, .tiles)
        assertEquals(workspace.rootTilingContainer.orientation, .h)
    }

    func testEmptyWorkspace_floating_fails() async {
        let workspace = Workspace.get(byName: name)
        await assertRun("layout floating", env: .defaultEnv.withWorkspaceName(name), exitCode: 2, stderr: [noWindowIsFocused])
        assertTrue(workspace.isEffectivelyEmpty)
    }

    func testEmptyWorkspace_tiling_isNoop() async {
        let workspace = Workspace.get(byName: name)
        await assertRun(
            "layout tiling",
            env: .defaultEnv.withWorkspaceName(name),
            exitCode: 0,
            stderr: ["Already in the requested tiling mode. Tip: use --fail-if-noop to exit with non-zero code"],
        )
        assertTrue(workspace.isEffectivelyEmpty)
    }

    func testEmptyWorkspace_tiling_failIfNoop() async {
        let workspace = Workspace.get(byName: name)
        await assertRun("layout tiling --fail-if-noop", env: .defaultEnv.withWorkspaceName(name), exitCode: 2, stderr: [])
        assertTrue(workspace.isEffectivelyEmpty)
    }

    func testTilingToFloating() async {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        await parseCommand("layout floating").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([.window(2)]))
        assertEquals(workspace.floatingWindows.map(\.windowId), [1])
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFloatingToTiling() async {
        let workspace = Workspace.get(byName: name)
        workspace.floatingWindowsContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }
        assertEquals(workspace.floatingWindows.map(\.windowId), [1])

        await parseCommand("layout tiling").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(workspace.floatingWindows, [])
        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1)]))
    }

    func testLayoutTilingOnTiledWindow_isNoop() async {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        await assertRun("layout tiling", exitCode: 0)
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2)]))
    }

    func testLayoutFloatingOnFloatingWindow_isNoop() async {
        let workspace = Workspace.get(byName: name)
        workspace.floatingWindowsContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        await assertRun("layout floating", exitCode: 0)
        assertEquals(workspace.floatingWindows.map(\.windowId), [1])
    }

    func testChangeTilingLayoutOnFloatingWindow_fails() async {
        let workspace = Workspace.get(byName: name)
        workspace.floatingWindowsContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        await assertRun("layout v_tiles", exitCode: 2, stderr: ["The window is non-tiling"])
        assertEquals(workspace.floatingWindows.map(\.windowId), [1])
    }

    func testTogglesAcrossFloatingAndTiling() async {
        let workspace = Workspace.get(byName: name)
        workspace.floatingWindowsContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        // The window is floating, so [.floating, .tiling] picks .tiling
        await parseCommand("layout floating tiling").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1)]))

        // Now it's tiled, so the same toggle picks .floating
        await parseCommand("layout floating tiling").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(workspace.floatingWindows.map(\.windowId), [1])
    }

    func testRoot_changesRootInsteadOfNestedParent() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            }
            TestWindow.new(id: 2, parent: $0)
        }
        assertEquals(root.orientation, .h)
        assertEquals(root.layout, .tiles)

        await parseCommand("layout --root v_accordion").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layout, .accordion)
        assertEquals(root.orientation, .v)
        assertEquals(root.layoutDescription, .v_accordion([.v_tiles([.window(1)]), .window(2)]))
    }

    func testRoot_emptyWorkspace_changeLayout() async {
        let workspace = Workspace.get(byName: name)
        assertTrue(workspace.isEffectivelyEmpty)

        await assertRun("layout --root accordion", env: .defaultEnv.withWorkspaceName(name), exitCode: 0)
        assertEquals(workspace.rootTilingContainer.layout, .accordion)
        assertEquals(workspace.rootTilingContainer.orientation, .h)
    }

    func testRoot_floatingFocusedWindow_changesRootTilingContainer() async {
        let workspace = Workspace.get(byName: name)
        workspace.floatingWindowsContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        await parseCommand("layout --root v_accordion").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(workspace.rootTilingContainer.layout, .accordion)
        assertEquals(workspace.rootTilingContainer.orientation, .v)
        assertEquals(workspace.floatingWindows.map(\.windowId), [1])
    }

    func testRoot_macosFullscreenFocusedWindow_changesRootTilingContainer() async {
        let workspace = Workspace.get(byName: name)
        assertEquals(TestWindow.new(id: 1, parent: workspace.macOsNativeFullscreenWindowsContainer).focusWindow(), true)

        // Without --root this would fail with "Can't change layout for macOS minimized, fullscreen…".
        await parseCommand("layout --root v_accordion").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(workspace.rootTilingContainer.layout, .accordion)
        assertEquals(workspace.rootTilingContainer.orientation, .v)
    }

    func testRoot_withWindowIdFlag_targetsThatWindowsWorkspaceRoot() async {
        let focusedRoot = Workspace.get(byName: "a").rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }
        let otherRoot = Workspace.get(byName: "b").rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0)
        }
        assertEquals(focusedRoot.layout, .tiles)
        assertEquals(otherRoot.layout, .tiles)

        await parseCommand("layout --root --window-id 2 v_accordion").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(otherRoot.layout, .accordion)
        assertEquals(otherRoot.orientation, .v)
        assertEquals(focusedRoot.layout, .tiles) // Focused workspace must be untouched
    }

    func testRoot_withWorkspaceFlag_targetsThatWorkspace() async {
        let focusedRoot = Workspace.get(byName: "a").rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }
        let otherRoot = Workspace.get(byName: "b").rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0)
        }
        assertEquals(focusedRoot.layout, .tiles)
        assertEquals(otherRoot.layout, .tiles)

        await parseCommand("layout --root --workspace b v_accordion").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(otherRoot.layout, .accordion)
        assertEquals(otherRoot.orientation, .v)
        assertEquals(focusedRoot.layout, .tiles) // Focused workspace must be untouched
    }

    func testRoot_toggleBetween_skipsMatching() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            }
            TestWindow.new(id: 2, parent: $0)
        }
        assertEquals(root.layoutDescription, .h_tiles([.v_tiles([.window(1)]), .window(2)]))

        await parseCommand("layout --root h_tiles h_accordion").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layout, .accordion)
        assertEquals(root.orientation, .h)
        assertEquals(root.layoutDescription, .h_accordion([.v_tiles([.window(1)]), .window(2)]))
    }

    func testRoot_alreadyMatches_isNoop() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2)]))

        await assertRun("layout --root h_tiles", exitCode: 0, stderr: ["Already in the requested h_tiles mode. Tip: use --fail-if-noop to exit with non-zero code"])
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2)]))
    }

    func testTilingDescriptions_allStartingStates() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }
        for (description, layout, orientation) in tilingDescriptions {
            for startLayout: Layout in [.tiles, .accordion] {
                for startOrientation: Orientation in [.h, .v] {
                    root.layout = startLayout
                    root.changeOrientation(startOrientation)
                    let msg = "layout \(description) on \(startLayout) \(startOrientation)"
                    let expectedLayout = layout ?? startLayout
                    let expectedOrientation = orientation ?? startOrientation
                    let isNoop = expectedLayout == startLayout && expectedOrientation == startOrientation

                    let result = await parseCommand("layout \(description)").cmdOrDie.run(.defaultEnv, .emptyStdin)
                    let noopMsg = "Already in the requested \(description) mode. Tip: use --fail-if-noop to exit with non-zero code"
                    assertEquals(result, CmdResult(stdout: [], stderr: isNoop ? [noopMsg] : [], exitCode: Int32ExitCode(rawValue: 0)), additionalMsg: msg)
                    assertEquals(root.layout, expectedLayout, additionalMsg: msg)
                    assertEquals(root.orientation, expectedOrientation, additionalMsg: msg)
                    assertEquals(root.children.map { ($0 as? Window)?.windowId }, [1, 2], additionalMsg: msg)
                }
            }
        }
    }

    func testTilingDescriptions_floatingWindow_fail() async {
        let workspace = Workspace.get(byName: name)
        workspace.floatingWindowsContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }
        for (description, _, _) in tilingDescriptions {
            await assertRun("layout \(description)", exitCode: 2, stdout: [], stderr: ["The window is non-tiling"])
            assertEquals(workspace.floatingWindows.map(\.windowId), [1])
        }
    }
}

/// The tiling layout descriptions, with the layout and the orientation they request (nil: keep the current one)
private let tilingDescriptions: [(String, Layout?, Orientation?)] = [
    ("h_accordion", .accordion, .h),
    ("v_accordion", .accordion, .v),
    ("h_tiles", .tiles, .h),
    ("v_tiles", .tiles, .v),
    ("accordion", .accordion, nil),
    ("tiles", .tiles, nil),
    ("horizontal", nil, .h),
    ("vertical", nil, .v),
]
