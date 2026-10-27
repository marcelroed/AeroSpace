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

    @Test
    func disablingWhileThereAreNoScreensFails() async {
        updateMonitors([])
        // Disabling unhides the windows of all workspaces in the layout, which waits for the screens
        for command in ["enable off", "enable toggle"] {
            let output = await runCmd(command)
            expectEqual(output, .fail("Can't disable \(aeroSpaceAppName) while there are no screens"), "\(command)")
            #expect(world.isEnabled, "\(command)")
        }
        expectEqual(world.activeMode, mainModeId)

        // Enabling still works: the layout does nothing until the screens come back
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
