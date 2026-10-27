@testable import AppBundle
import AppKit
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct ClosedWindowsCacheTest {
    @Test
    func restoreClosedWindowsCache() async throws {
        defer { resetClosedWindowsCache() }
        let workspace = setUpTree("h_tiles(1:2 v_accordion:3(2 3)) floating(4) macos_fullscreen(5) macos_hidden(6)")
        let accordion = testWindow(2).parent
        cacheClosedWindowIfNeeded()

        // Scramble the tree. Tests find windows only in workspaces, so keep the tiling windows in another workspace
        let other = Workspace.get(byName: "other")
        for window in workspace.rootTilingContainer.allLeafWindowsRecursive {
            window.move(to: other.rootTilingContainer, at: 0, weight: .value(1))
        }
        for id: UInt32 in [4, 5] {
            testWindow(id).move(to: workspace.rootTilingContainer, weight: .value(1))
        }
        let orphan = TestWindow.new(id: 7, parent: workspace.rootTilingContainer) // Not cached
        try await expectEqual(restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: orphan), false)
        expectEqual(describeTree(), "h_tiles(v_accordion() 4 5 *7) macos_hidden(6)")

        try await expectEqual(restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: testWindow(1)), true)
        // The orphan is bound next to the most recent window
        expectEqual(describeTree(weights: true), "h_tiles(1:2 v_accordion:3(2:1 3:1 *7:1)) floating(4 6 5)")
        // The restored workspace children are in the order of the cache, not in the canonical order of describeTree
        expectEqual(workspace.children.map { ($0 as? Container)?.kind }, [.floating, .macosFullscreen, .macosHiddenApp, .tiling])
        #expect(other.isEffectivelyEmpty)
        #expect(testWindow(2).parent !== accordion) // The tree is recreated
        expectEqual(focus.workspace, workspace)
    }
}
