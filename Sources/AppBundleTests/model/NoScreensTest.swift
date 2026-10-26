@testable import AppBundle
import AppKit
import Common
import Testing

/// `NSScreen.screens` is briefly empty during display reconfiguration (e.g. on display wake). RB-01
@MainActor
@Suite(.aeroSpaceGlobalState)
struct NoScreensTest: AeroSpaceTestSuite {
    @Test
    func monitorApproximationFallsBackToMainMonitorWhenThereAreNoScreens() {
        let workspace = Workspace.get(byName: name)
        #expect(workspace.focusWorkspace())
        $noScreensForTests.withValue(true) {
            #expect(monitorInfos.isEmpty)
            #expect(CGPoint(x: 100, y: 100).monitorApproximation.rect.topLeftCorner == mainMonitorInfo.rect.topLeftCorner)
            #expect(workspace.workspaceMonitor.rect.topLeftCorner == mainMonitorInfo.rect.topLeftCorner)
        }
    }

    @Test
    func visibleWorkspaceSurvivesTransientAbsenceOfScreens() {
        let workspace = Workspace.get(byName: name)
        #expect(workspace.focusWorkspace())
        $noScreensForTests.withValue(true) {
            gcMonitors()
            #expect(workspace.isVisible)
        }
        gcMonitors() // The screens are back
        #expect(mainMonitorInfo.activeWorkspace == workspace)
    }

    @Test
    func focusingAnotherWorkspaceWhileThereAreNoScreensKeepsTheVisibleWorkspaces() {
        let visible = Workspace.get(byName: name)
        #expect(visible.focusWorkspace())
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
        let visible = Workspace.get(byName: name)
        #expect(visible.focusWorkspace())
        await $noScreensForTests.withValue(true) {
            // The monitor of the focused workspace is the fake mainMonitorInfo meanwhile, not the focused monitor
            let result = await parseCommand("summon-workspace other").cmdOrDie.run(.defaultEnv, .emptyStdin)
            #expect(result.exitCode.rawValue != 0)
        }
        #expect(visible.isVisible)
        #expect(!Workspace.get(byName: "other").isVisible)
        #expect(focus.workspace == visible)
    }

    @Test
    func windowsOfVisibleWorkspacesCanBeFocusedWhileThereAreNoScreens() {
        let workspace = Workspace.get(byName: name)
        let window1 = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let window2 = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        #expect(window1.focusWindow())
        $noScreensForTests.withValue(true) {
            #expect(window2.focusWindow())
        }
        #expect(focus.windowOrNil == window2)
        #expect(workspace.isVisible)
    }

    @Test
    func focusCallbacksDontFireWhenTheScreensDisappearAndComeBack() async {
        #expect(Workspace.get(byName: name).focusWorkspace())
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
        let workspace = Workspace.get(byName: name)
        let window1 = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        #expect(window1.focusWindow())
        await checkOnFocusChangedCallbacks_nonCancellable() // Remember the focus
        config.onFocusChanged = parseCommand("mode on-focus-changed").cmdOrDie

        await $noScreensForTests.withValue(true) {
            window1.closeAxWindow()
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
