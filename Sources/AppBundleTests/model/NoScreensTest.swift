@testable import AppBundle
import AppKit
import Common
import Testing

/// `NSScreen.screens` is briefly empty during display reconfiguration (e.g. on display wake). RB-01
@Suite(.aeroSpaceGlobalState)
struct NoScreensTest {
    @Test
    func monitorApproximationFallsBackToMainMonitorWhenThereAreNoScreens() {
        let workspace = focus.workspace
        $noScreensForTests.withValue(true) {
            #expect(monitorInfos.isEmpty)
            expectEqual(CGPoint(x: 100, y: 100).monitorApproximation.rect.topLeftCorner, mainMonitorInfo.rect.topLeftCorner)
            expectEqual(workspace.workspaceMonitor.rect.topLeftCorner, mainMonitorInfo.rect.topLeftCorner)
        }
    }

    @Test
    func visibleWorkspaceSurvivesTransientAbsenceOfScreens() {
        let workspace = focus.workspace
        $noScreensForTests.withValue(true) {
            gcMonitors()
            #expect(workspace.isVisible)
        }
        gcMonitors() // The screens are back
        expectEqual(mainMonitorInfo.activeWorkspace, workspace)
    }

    @Test
    func focusingAnotherWorkspaceWhileThereAreNoScreensKeepsTheVisibleWorkspaces() {
        let visible = focus.workspace
        let other = Workspace.get(byName: "other")
        $noScreensForTests.withValue(true) {
            // The workspaceMonitor of every workspace is the fake mainMonitorInfo meanwhile
            #expect(!other.focusWorkspace())
            expectEqual(focus.workspace, visible)
        }
        #expect(visible.isVisible)
        #expect(!other.isVisible)
    }

    @Test
    func summoningWorkspaceWhileThereAreNoScreensKeepsTheVisibleWorkspaces() async {
        let visible = focus.workspace
        // The monitor of the focused workspace is the fake mainMonitorInfo meanwhile, not the focused monitor
        let output = await $noScreensForTests.withValue(true) { await runCmd("summon-workspace other") }
        expectEqual(output, .fail("Can't summon workspace 'other' while there are no screens"))
        #expect(visible.isVisible)
        #expect(!Workspace.get(byName: "other").isVisible)
        expectEqual(focus.workspace, visible)
    }

    @Test
    func disablingWhileThereAreNoScreensFails() async {
        await $noScreensForTests.withValue(true) {
            // Disabling lays out the windows of all workspaces, on the fake mainMonitorInfo meanwhile
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
    }

    @Test
    func windowsOfVisibleWorkspacesCanBeFocusedWhileThereAreNoScreens() {
        let workspace = setUpTree("h_tiles(*1 2)")
        $noScreensForTests.withValue(true) {
            #expect(testWindow(2).focusWindow())
        }
        expectEqual(focus.windowOrNil?.windowId, 2)
        #expect(workspace.isVisible)
    }

    @Test
    func focusCallbacksDontFireWhenTheScreensDisappearAndComeBack() async {
        await checkOnFocusChangedCallbacks_nonCancellable() // Remember the focus
        world.config.onFocusChanged = parseCommand("mode on-focus-changed").cmdOrDie
        world.config.onFocusedMonitorChanged = parseCommand("mode on-focused-monitor-changed").cmdOrDie

        await $noScreensForTests.withValue(true) {
            await checkOnFocusChangedCallbacks_nonCancellable()
        }
        expectEqual(world.activeMode, mainModeId)

        await checkOnFocusChangedCallbacks_nonCancellable() // The screens are back
        expectEqual(world.activeMode, mainModeId)
    }

    @Test
    func focusChangeWhileThereAreNoScreensIsReportedWhenTheScreensComeBack() async {
        setUpTree("h_tiles(*1 2)")
        await checkOnFocusChangedCallbacks_nonCancellable() // Remember the focus
        world.config.onFocusChanged = parseCommand("mode on-focus-changed").cmdOrDie

        await $noScreensForTests.withValue(true) {
            testWindow(1).closeAxWindow()
            expectEqual(focus.windowOrNil?.windowId, 2)
            await checkOnFocusChangedCallbacks_nonCancellable()
        }
        expectEqual(world.activeMode, mainModeId)

        await checkOnFocusChangedCallbacks_nonCancellable() // The screens are back
        expectEqual(world.activeMode, "on-focus-changed")

        world.activeMode = mainModeId
        await checkOnFocusChangedCallbacks_nonCancellable()
        expectEqual(world.activeMode, mainModeId) // Reported only once
    }
}
