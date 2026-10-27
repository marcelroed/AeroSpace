@testable import AppBundle
import AppKit
import Common
import Testing

/// How the tree helpers, commands and callbacks treat a window depending on the kind of its parent
@Suite(.aeroSpaceGlobalState)
struct WindowParentTest {
    @Test
    func windowProperties() {
        // In workspace "a", which isn't focused: so that a lookup that falls back to the focused workspace fails the test
        setUpTree("h_tiles(1 7) floating(2) macos_fullscreen(3) macos_hidden(4) macos_minimized(5) macos_popup(6)", workspace: "a")
        testWindow(7).unbindFromParent()
        let workspace = Workspace.get(byName: "a")
        #expect(workspace != focus.workspace)
        let monitorName = workspace.workspaceMonitor.name
        let rows: [(id: WindowId, placement: WindowPlacement?, isFloating: Bool, isInWorkspace: Bool)] = [
            (1, .tiling(workspace.existingRootTilingContainer.orDie()), false, true),
            (2, .floating(workspace), true, true),
            (3, .macosFullscreen(workspace), false, true),
            (4, .macosHiddenApp(workspace), false, true),
            (5, .macosMinimized, false, false),
            (6, .macosPopup, false, false),
            (7, nil, false, false), // Unbound
        ]
        for row in rows {
            let window = testWindow(row.id)
            expectEqual(window.placement, row.placement, "placement of \(row.id)")
            expectEqual(window.isFloating, row.isFloating, "isFloating of \(row.id)")
            expectEqual(window.nodeWorkspace?.name, row.isInWorkspace ? "a" : nil, "nodeWorkspace of \(row.id)")
            expectEqual(window.nodeMonitor?.name, row.isInWorkspace ? monitorName : nil, "nodeMonitor of \(row.id)")
            expectEqual(window.toLiveFocusOrNil()?.workspace.name, row.isInWorkspace ? "a" : nil, "toLiveFocusOrNil of \(row.id)")
        }
        expectEqual(macosMinimizedWindowsContainer.nodeMonitor?.name, nil)
        expectEqual(macosPopupWindowsContainer.nodeMonitor?.name, nil)
        expectEqual(workspace.existingContainer(.floating)?.nodeMonitor?.name, monitorName)

        expectEqual(rows.map { testWindow($0.id).focusWindow() }, rows.map(\.isInWorkspace))
        expectEqual(focus.windowOrNil?.windowId, 4) // The last window that could be focused
    }

    @Test(arguments: [
        ("floating", "move left", .fail("moving floating windows isn't yet supported"), "h_tiles(1)"),
        ("macos_fullscreen", "move left", .fail("moving macOS fullscreen, minimized windows and windows of hidden apps isn't yet supported. This behavior is subject to change"), "h_tiles(1)"),
        ("macos_hidden", "move left", .fail("moving macOS fullscreen, minimized windows and windows of hidden apps isn't yet supported. This behavior is subject to change"), "h_tiles(1)"),
        ("macos_fullscreen", "layout tiles", .fail("Can't change layout for macOS minimized, fullscreen windows or windows or hidden apps. This behavior is subject to change"), "h_tiles(1)"),
        ("macos_hidden", "layout tiles", .fail("Can't change layout for macOS minimized, fullscreen windows or windows or hidden apps. This behavior is subject to change"), "h_tiles(1)"),
        // --root changes the root container instead
        ("macos_fullscreen", "layout --root v_accordion", .ok, "v_accordion(1)"),
        ("macos_hidden", "layout --root v_accordion", .ok, "v_accordion(1)"),
    ] as [(String, String, CmdOutput, String)])
    func commandsOnUnsupportedWindows(container: String, command: String, expected: CmdOutput, root: String) async {
        setUpTree("h_tiles(1) \(container)(*2)")
        let output = await runCmd(command)
        expectEqual(output, expected)
        expectEqual(describeTree(), "\(root) \(container)(*2)")
    }

    @Test
    func aFloatingWindowGetsItsSizeBackAfterTiling() async {
        setUpTree("h_tiles(1) floating(*2)")
        let floating = testWindow(2)
        floating.rect = Rect(topLeftX: 10, topLeftY: 20, width: 100, height: 50)

        var output = await runCmd("layout floating tiling")
        expectEqual(output, .ok)
        expectEqual(describeTree(), "h_tiles(1 *2)")
        expectEqual(floating.lastFloatingSize, CGSize(width: 100, height: 50))

        output = await runCmd("layout tiling floating")
        expectEqual(output, .ok)
        expectEqual(describeTree(), "h_tiles(1) floating(*2)")
        expectEqual(floating.setAxFrameHistory.last, AxFrame(topLeft: nil, size: CGSize(width: 100, height: 50)))
    }

    @Test
    func runOnWindowDetectedSkipsPopupAndUnboundWindows() async {
        let workspace = focus.workspace
        world.config.onWindowDetected = [
            WindowDetectedCallback(matcher: .command(.empty), run: parseCommand("workspace callback-ran").cmdOrDie),
        ]
        world.layoutForNextDetectedWindow = .floating

        let popup = TestWindow.new(id: 1, parent: macosPopupWindowsContainer)
        await runOnWindowDetected(ifConventional: popup, isStartup: false)
        let unbound = TestWindow.new(id: 2, parent: workspace.rootTilingContainerCreatingIfNeeded())
        unbound.unbindFromParent()
        await runOnWindowDetected(ifConventional: unbound, isStartup: false)
        expectEqual(world.layoutForNextDetectedWindow, .floating)
        expectEqual(focus.workspace, workspace)
        #expect(popup.parent === macosPopupWindowsContainer)
        expectEqual(unbound.parent, nil)

        let minimized = TestWindow.new(id: 3, parent: macosMinimizedWindowsContainer)
        await runOnWindowDetected(ifConventional: minimized, isStartup: false)
        expectEqual(world.layoutForNextDetectedWindow, nil)

        world.layoutForNextDetectedWindow = .floating
        let tiling = TestWindow.new(id: 4, parent: workspace.rootTilingContainerCreatingIfNeeded())
        await runOnWindowDetected(ifConventional: tiling, isStartup: false)
        expectEqual(world.layoutForNextDetectedWindow, nil)
        #expect(tiling.isFloating)
        expectEqual(focus.workspace.name, "callback-ran")
    }
}
