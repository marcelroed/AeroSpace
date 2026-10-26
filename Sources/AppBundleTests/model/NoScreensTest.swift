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
}
