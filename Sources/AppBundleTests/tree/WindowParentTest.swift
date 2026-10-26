@testable import AppBundle
import Common
import Testing

/// How the tree helpers, commands and callbacks treat a window depending on the kind of its parent
@MainActor
@Suite(.aeroSpaceGlobalState)
struct WindowParentTest: AeroSpaceTestSuite {
    @Test
    func testIsFloating() {
        let windows = windowOfEveryParentKind(Workspace.get(byName: name))
        assertEquals(windows.map(\.isFloating), [false, true, false, false, false, false, false])
    }

    @Test
    func testNodeWorkspaceAndNodeMonitor() {
        let workspace = Workspace.get(byName: name)
        let windows = windowOfEveryParentKind(workspace)
        let workspaceName = workspace.name
        assertEquals(windows.map { $0.nodeWorkspace?.name }, [workspaceName, workspaceName, workspaceName, workspaceName, nil, nil, nil])
        let monitorName = workspace.workspaceMonitor.name
        assertEquals(windows.map { $0.nodeMonitor?.name }, [monitorName, monitorName, monitorName, monitorName, nil, nil, nil])
        assertEquals(macosMinimizedWindowsContainer.nodeMonitor?.name, nil)
        assertEquals(macosPopupWindowsContainer.nodeMonitor?.name, nil)
        assertEquals(workspace.floatingWindowsContainer.nodeMonitor?.name, monitorName)
    }

    @Test
    func testFocusWindow() {
        let workspace = Workspace.get(byName: name)
        let windows = windowOfEveryParentKind(workspace)
        assertEquals(windows.map { $0.toLiveFocusOrNil()?.workspace.name }, [name, name, name, name, nil, nil, nil])
        assertEquals(windows.map { $0.focusWindow() }, [true, true, true, true, false, false, false])
        assertEquals(focus.windowOrNil?.windowId, 4) // The last window that could be focused
    }

    @Test
    func testMoveFloatingWindow() async {
        let workspace = Workspace.get(byName: name)
        TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertTrue(TestWindow.new(id: 2, parent: workspace.floatingWindowsContainer).focusWindow())
        let result = await parseCommand("move left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stdout, [])
        assertEquals(result.stderr, ["moving floating windows isn't yet supported"])
    }

    @Test
    func testMoveAndLayoutMacosUnconventionalWindows() async {
        let workspace = Workspace.get(byName: name)
        TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let fullscreen = TestWindow.new(id: 2, parent: workspace.macOsNativeFullscreenWindowsContainer)
        let hiddenApp = TestWindow.new(id: 3, parent: workspace.macOsNativeHiddenAppsWindowsContainer)
        for window in [fullscreen, hiddenApp] {
            assertTrue(window.focusWindow())

            let move = await parseCommand("move left").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(move.exitCode.rawValue, 2)
            assertEquals(move.stdout, [])
            assertEquals(move.stderr, ["moving macOS fullscreen, minimized windows and windows of hidden apps isn't yet supported. This behavior is subject to change"])

            let layout = await parseCommand("layout tiles").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(layout.exitCode.rawValue, 2)
            assertEquals(layout.stdout, [])
            assertEquals(layout.stderr, ["Can't change layout for macOS minimized, fullscreen windows or windows or hidden apps. This behavior is subject to change"])

            // --root changes the root container instead
            let layoutRoot = await parseCommand("layout --root v_accordion").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(layoutRoot.exitCode.rawValue, 0)
            assertEquals(workspace.rootTilingContainer.layoutDescription, .v_accordion([.window(1)]))
            workspace.rootTilingContainer.layout = .tiles
            workspace.rootTilingContainer.changeOrientation(.h)
        }
        assertEquals(fullscreen.parent === workspace.macOsNativeFullscreenWindowsContainer, true)
        assertEquals(hiddenApp.parent === workspace.macOsNativeHiddenAppsWindowsContainer, true)
    }

    @Test
    func testRunOnWindowDetectedSkipsPopupAndUnboundWindows() async {
        let workspace = Workspace.get(byName: name)
        assertTrue(workspace.focusWorkspace())
        config.onWindowDetected = [
            WindowDetectedCallback(matcher: .command(.empty), run: parseCommand("workspace callback-ran").cmdOrDie),
        ]
        global_layoutForNextDetectedWindow = .floating

        let popup = TestWindow.new(id: 1, parent: macosPopupWindowsContainer)
        await runOnWindowDetected(ifConventional: popup)
        let unbound = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        unbound.unbindFromParent()
        await runOnWindowDetected(ifConventional: unbound)
        assertEquals(global_layoutForNextDetectedWindow, .floating)
        assertEquals(focus.workspace.name, name)
        assertEquals(popup.parent === macosPopupWindowsContainer, true)
        assertNil(unbound.parent)

        let minimized = TestWindow.new(id: 3, parent: macosMinimizedWindowsContainer)
        await runOnWindowDetected(ifConventional: minimized)
        assertNil(global_layoutForNextDetectedWindow)

        global_layoutForNextDetectedWindow = .floating
        let tiling = TestWindow.new(id: 4, parent: workspace.rootTilingContainer)
        await runOnWindowDetected(ifConventional: tiling)
        assertNil(global_layoutForNextDetectedWindow)
        assertEquals(tiling.isFloating, true)
        assertEquals(focus.workspace.name, "callback-ran")
    }

    /// tiling, floating, macOS fullscreen, window of a hidden app, minimized, popup, unbound
    private func windowOfEveryParentKind(_ workspace: Workspace) -> [Window] {
        let unbound = TestWindow.new(id: 7, parent: workspace.rootTilingContainer)
        unbound.unbindFromParent()
        return [
            TestWindow.new(id: 1, parent: workspace.rootTilingContainer),
            TestWindow.new(id: 2, parent: workspace.floatingWindowsContainer),
            TestWindow.new(id: 3, parent: workspace.macOsNativeFullscreenWindowsContainer),
            TestWindow.new(id: 4, parent: workspace.macOsNativeHiddenAppsWindowsContainer),
            TestWindow.new(id: 5, parent: macosMinimizedWindowsContainer),
            TestWindow.new(id: 6, parent: macosPopupWindowsContainer),
            unbound,
        ]
    }
}
