@testable import AppBundle
import AppKit
import Common
import Testing

/// How the tree helpers, commands and callbacks treat a window depending on the kind of its parent
@MainActor
@Suite(.aeroSpaceGlobalState)
struct WindowParentTest {
    @Test
    func isFloating() {
        let windows = windowOfEveryParentKind()
        #expect(windows.map(\.isFloating) == [false, true, false, false, false, false, false])
    }

    @Test
    func nodeWorkspaceAndNodeMonitor() {
        let windows = windowOfEveryParentKind()
        let workspace = focus.workspace
        let workspaceName = workspace.name
        #expect(windows.map { $0.nodeWorkspace?.name } == [workspaceName, workspaceName, workspaceName, workspaceName, nil, nil, nil])
        let monitorName = workspace.workspaceMonitor.name
        #expect(windows.map { $0.nodeMonitor?.name } == [monitorName, monitorName, monitorName, monitorName, nil, nil, nil])
        #expect(macosMinimizedWindowsContainer.nodeMonitor?.name == nil)
        #expect(macosPopupWindowsContainer.nodeMonitor?.name == nil)
        #expect(workspace.floatingWindowsContainer.nodeMonitor?.name == monitorName)
    }

    @Test
    func focusWindow() {
        let windows = windowOfEveryParentKind()
        let name = focus.workspace.name
        #expect(windows.map { $0.toLiveFocusOrNil()?.workspace.name } == [name, name, name, name, nil, nil, nil])
        #expect(windows.map { $0.focusWindow() } == [true, true, true, true, false, false, false])
        #expect(focus.windowOrNil?.windowId == 4) // The last window that could be focused
    }

    @Test
    func moveFloatingWindow() async {
        setUpTree("h_tiles(1) floating(*2)")
        let output = await runCmd("move left")
        #expect(output == .fail("moving floating windows isn't yet supported"))
    }

    @Test(arguments: ["macos_fullscreen", "macos_hidden"], [
        ("move left", .fail("moving macOS fullscreen, minimized windows and windows of hidden apps isn't yet supported. This behavior is subject to change"), "h_tiles(1)"),
        ("layout tiles", .fail("Can't change layout for macOS minimized, fullscreen windows or windows or hidden apps. This behavior is subject to change"), "h_tiles(1)"),
        ("layout --root v_accordion", .ok, "v_accordion(1)"), // --root changes the root container instead
    ] as [(String, CmdOutput, String)])
    func moveAndLayoutMacosUnconventionalWindow(container: String, step: (command: String, expected: CmdOutput, root: String)) async {
        setUpTree("h_tiles(1) \(container)(*2)")
        let output = await runCmd(step.command)
        #expect(output == step.expected)
        #expect(describeTree() == "\(step.root) \(container)(*2)")
    }

    @Test
    func layoutFloatingAndTilingWindows() async {
        setUpTree("h_tiles(1) floating(*2)")
        let floating = testWindow(2)
        floating.lastFloatingSize = CGSize(width: 100, height: 50)

        for command in ["layout h_tiles", "layout accordion", "layout vertical"] {
            let output = await runCmd(command)
            #expect(output == .fail("The window is non-tiling"))
        }
        var output = await runCmd("layout floating")
        #expect(output == CmdOutput(stderr: ["Already in the requested floating mode. Tip: use --fail-if-noop to exit with non-zero code"]))

        output = await runCmd("layout floating tiling")
        #expect(output == .ok)
        #expect(describeTree() == "h_tiles(1 *2)")
        #expect(floating.lastFloatingSize == CGSize(width: 100, height: 50))

        output = await runCmd("layout tiling")
        #expect(output == CmdOutput(stderr: ["Already in the requested tiling mode. Tip: use --fail-if-noop to exit with non-zero code"]))
        output = await runCmd("layout v_accordion")
        #expect(output == .ok)
        #expect(describeTree() == "v_accordion(1 *2)")

        output = await runCmd("layout tiling floating")
        #expect(output == .ok)
        #expect(describeTree() == "v_accordion(1) floating(*2)")
        #expect(floating.setAxFrameHistory.last == AxFrame(topLeft: nil, size: CGSize(width: 100, height: 50)))
    }

    @Test
    func runOnWindowDetectedSkipsPopupAndUnboundWindows() async {
        let workspace = focus.workspace
        config.onWindowDetected = [
            WindowDetectedCallback(matcher: .command(.empty), run: parseCommand("workspace callback-ran").cmdOrDie),
        ]
        global_layoutForNextDetectedWindow = .floating

        let popup = TestWindow.new(id: 1, parent: macosPopupWindowsContainer)
        await runOnWindowDetected(ifConventional: popup)
        let unbound = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        unbound.unbindFromParent()
        await runOnWindowDetected(ifConventional: unbound)
        #expect(global_layoutForNextDetectedWindow == .floating)
        #expect(focus.workspace == workspace)
        #expect(popup.parent === macosPopupWindowsContainer)
        #expect(unbound.parent == nil)

        let minimized = TestWindow.new(id: 3, parent: macosMinimizedWindowsContainer)
        await runOnWindowDetected(ifConventional: minimized)
        #expect(global_layoutForNextDetectedWindow == nil)

        global_layoutForNextDetectedWindow = .floating
        let tiling = TestWindow.new(id: 4, parent: workspace.rootTilingContainer)
        await runOnWindowDetected(ifConventional: tiling)
        #expect(global_layoutForNextDetectedWindow == nil)
        #expect(tiling.isFloating)
        #expect(focus.workspace.name == "callback-ran")
    }

    /// tiling, floating, macOS fullscreen, window of a hidden app, minimized, popup, unbound
    private func windowOfEveryParentKind() -> [Window] {
        setUpTree("h_tiles(1 7) floating(2) macos_fullscreen(3) macos_hidden(4) macos_minimized(5) macos_popup(6)")
        testWindow(7).unbindFromParent()
        return (1 ... 7).map(testWindow)
    }
}
