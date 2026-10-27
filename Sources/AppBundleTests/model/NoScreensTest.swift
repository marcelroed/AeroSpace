@testable import AppBundle
import AppKit
import Common
import Testing

/// `NSScreen.screens` is briefly empty during display reconfiguration (e.g. on display wake). RB-01
@Suite(.aeroSpaceGlobalState)
struct NoScreensTest {
    @Test
    func theMonitorsAndTheirWorkspacesStayWhileThereAreNoScreens() {
        updateMonitors([testMonitor, rightTestMonitor])
        let left = focus.workspace
        let right = rightTestMonitor.activeWorkspace

        #expect(!updateMonitors([]))
        expectEqual(world.monitors.all.map(\.name), [testMonitor.name, rightTestMonitor.name])
        expectEqual(right.workspaceMonitor.name, rightTestMonitor.name)
        expectEqual(world.monitors.approximation(CGPoint(x: 2000, y: 100)).activeWorkspace, right)

        #expect(updateMonitors([testMonitor, rightTestMonitor])) // The screens are back
        expectEqual(world.monitors.all.map(\.activeWorkspace), [left, right])
    }

    @Test
    func focusingAnotherWorkspaceWhileThereAreNoScreensKeepsTheVisibleWorkspaces() {
        let visible = focus.workspace
        let other = Workspace.get(byName: "other")
        updateMonitors([])
        #expect(!other.focusWorkspace())
        expectEqual(focus.workspace, visible)
        #expect(visible.isVisible)
        #expect(!other.isVisible)
    }

    @Test
    func summoningWorkspaceWhileThereAreNoScreensKeepsTheVisibleWorkspaces() async {
        let visible = focus.workspace
        updateMonitors([])
        let output = await runCmd("summon-workspace other")
        expectEqual(output, .fail("Can't summon workspace 'other' while there are no screens"))
        #expect(visible.isVisible)
        #expect(!Workspace.get(byName: "other").isVisible)
        expectEqual(focus.workspace, visible)
    }

    /// No screens is a normal state, not a bug (RB-40): the commands that need them fail with a message and change nothing
    @Test(arguments: [
        // Disabling unhides the windows of all workspaces in the layout, which waits for the screens
        ("enable off", "Can't disable \(aeroSpaceAppName) while there are no screens"),
        ("enable toggle", "Can't disable \(aeroSpaceAppName) while there are no screens"),
        ("focus --boundaries all-monitors-outer-frame left", "Can't find monitors in direction left while there are no screens"),
        ("move --boundaries all-monitors-outer-frame left", "Can't find monitors in direction left while there are no screens"),
        ("focus-monitor left", "Can't find monitors in direction left while there are no screens"),
        ("focus-monitor next", "Can't find the next monitor while there are no screens"),
        ("focus-monitor --wrap-around next", "Can't find the next monitor while there are no screens"),
        ("focus-monitor prev", "Can't find the prev monitor while there are no screens"),
        // With screens, both patterns match "Test Monitor"
        ("focus-monitor 1", "Can't find monitors that match the pattern(s) while there are no screens"),
        ("focus-monitor test", "Can't find monitors that match the pattern(s) while there are no screens"),
        ("move-workspace-to-monitor next", "Can't find the next monitor while there are no screens"),
        // Only the visible workspaces can be focused (RB-31: the command used to succeed)
        ("workspace-back-and-forth", "Can't focus workspace 'prev' while there are no screens"),
    ] as [(String, String)])
    func commandsFailWithoutScreens(command: String, error: String) async {
        let workspace = setUpTree("h_tiles(*1 2)")
        world.focusStore.prevWorkspaceName = "prev"
        updateMonitors([])
        let output = await runCmd(command)
        expectEqual(output, .fail(error))
        expectEqual(describeTree(), "h_tiles(*1 2)")
        expectEqual(focus.workspace, workspace)
        #expect(world.isEnabled)
    }

    /// Enabling doesn't need the screens: the layout does nothing until they come back
    @Test
    func enablingWorksWithoutScreens() async {
        updateMonitors([])
        world.isEnabled = false
        let output = await runCmd("enable on")
        expectEqual(output, .ok)
        #expect(world.isEnabled)
    }

    @Test
    func windowsOfVisibleWorkspacesCanBeFocusedWhileThereAreNoScreens() {
        let workspace = setUpTree("h_tiles(*1 2)")
        updateMonitors([])
        #expect(testWindow(2).focusWindow())
        expectEqual(focus.windowOrNil?.windowId, 2)
        #expect(workspace.isVisible)
    }

    @Test
    func focusCallbacksDontFireWhenTheScreensDisappearAndComeBack() async {
        await checkOnFocusChangedCallbacks_nonCancellable() // Remember the focus
        world.config.onFocusChanged = parseCommand("mode on-focus-changed").cmdOrDie
        world.config.onFocusedMonitorChanged = parseCommand("mode on-focused-monitor-changed").cmdOrDie

        updateMonitors([])
        await checkOnFocusChangedCallbacks_nonCancellable()
        expectEqual(world.activeMode, mainModeId)

        updateMonitors([testMonitor]) // The screens are back
        await checkOnFocusChangedCallbacks_nonCancellable()
        expectEqual(world.activeMode, mainModeId)
    }

    @Test
    func focusChangeWhileThereAreNoScreensIsReportedWhenTheScreensComeBack() async {
        setUpTree("h_tiles(*1 2)")
        await checkOnFocusChangedCallbacks_nonCancellable() // Remember the focus
        world.config.onFocusChanged = parseCommand("mode on-focus-changed").cmdOrDie

        updateMonitors([])
        testWindow(1).closeAxWindow()
        expectEqual(focus.windowOrNil?.windowId, 2)
        await checkOnFocusChangedCallbacks_nonCancellable()
        expectEqual(world.activeMode, mainModeId)

        updateMonitors([testMonitor]) // The screens are back
        await checkOnFocusChangedCallbacks_nonCancellable()
        expectEqual(world.activeMode, "on-focus-changed")

        world.activeMode = mainModeId
        await checkOnFocusChangedCallbacks_nonCancellable()
        expectEqual(world.activeMode, mainModeId) // Reported only once
    }
}
