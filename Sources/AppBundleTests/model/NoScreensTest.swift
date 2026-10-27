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
            #expect(CGPoint(x: 100, y: 100).monitorApproximation.rect.topLeftCorner == mainMonitorInfo.rect.topLeftCorner)
            #expect(workspace.workspaceMonitor.rect.topLeftCorner == mainMonitorInfo.rect.topLeftCorner)
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
        #expect(mainMonitorInfo.activeWorkspace == workspace)
    }

    @Test
    func focusingAnotherWorkspaceWhileThereAreNoScreensKeepsTheVisibleWorkspaces() {
        let visible = focus.workspace
        let other = Workspace.get(byName: "other")
        $noScreensForTests.withValue(true) {
            // The workspaceMonitor of every workspace is the fake mainMonitorInfo meanwhile
            #expect(!other.focusWorkspace())
            #expect(focus.workspace == visible)
        }
        #expect(visible.isVisible)
        #expect(!other.isVisible)
    }

    @Test
    func summoningWorkspaceWhileThereAreNoScreensKeepsTheVisibleWorkspaces() async {
        let visible = focus.workspace
        // The monitor of the focused workspace is the fake mainMonitorInfo meanwhile, not the focused monitor
        let output = await $noScreensForTests.withValue(true) { await runCmd("summon-workspace other") }
        #expect(output == .fail("Can't summon workspace 'other' while there are no screens"))
        #expect(visible.isVisible)
        #expect(!Workspace.get(byName: "other").isVisible)
        #expect(focus.workspace == visible)
    }

    @Test
    func disablingWhileThereAreNoScreensFails() async {
        await $noScreensForTests.withValue(true) {
            // Disabling lays out the windows of all workspaces, on the fake mainMonitorInfo meanwhile
            for command in ["enable off", "enable toggle"] {
                let output = await runCmd(command)
                #expect(output == .fail("Can't disable \(aeroSpaceAppName) while there are no screens"), "\(command)")
                #expect(TrayMenuModel.shared.isEnabled, "\(command)")
            }
            #expect(activeMode == mainModeId)

            // Enabling still works: the layout does nothing until the screens come back
            TrayMenuModel.shared.isEnabled = false
            let output = await runCmd("enable on")
            #expect(output == .ok)
            #expect(TrayMenuModel.shared.isEnabled)
        }
    }

    @Test
    func windowsOfVisibleWorkspacesCanBeFocusedWhileThereAreNoScreens() {
        let workspace = setUpTree("h_tiles(*1 2)")
        $noScreensForTests.withValue(true) {
            #expect(testWindow(2).focusWindow())
        }
        #expect(focus.windowOrNil?.windowId == 2)
        #expect(workspace.isVisible)
    }

    @Test
    func focusCallbacksDontFireWhenTheScreensDisappearAndComeBack() async {
        await checkOnFocusChangedCallbacks_nonCancellable() // Remember the focus
        config.onFocusChanged = parseCommand("mode on-focus-changed").cmdOrDie
        config.onFocusedMonitorChanged = parseCommand("mode on-focused-monitor-changed").cmdOrDie

        await $noScreensForTests.withValue(true) {
            await checkOnFocusChangedCallbacks_nonCancellable()
        }
        #expect(activeMode == mainModeId)

        await checkOnFocusChangedCallbacks_nonCancellable() // The screens are back
        #expect(activeMode == mainModeId)
    }

    @Test
    func focusChangeWhileThereAreNoScreensIsReportedWhenTheScreensComeBack() async {
        setUpTree("h_tiles(*1 2)")
        await checkOnFocusChangedCallbacks_nonCancellable() // Remember the focus
        config.onFocusChanged = parseCommand("mode on-focus-changed").cmdOrDie

        await $noScreensForTests.withValue(true) {
            testWindow(1).closeAxWindow()
            #expect(focus.windowOrNil?.windowId == 2)
            await checkOnFocusChangedCallbacks_nonCancellable()
        }
        #expect(activeMode == mainModeId)

        await checkOnFocusChangedCallbacks_nonCancellable() // The screens are back
        #expect(activeMode == "on-focus-changed")

        activeMode = mainModeId
        await checkOnFocusChangedCallbacks_nonCancellable()
        #expect(activeMode == mainModeId) // Reported only once
    }
}
