@testable import AppBundle
import AppKit
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct ClosedWindowsCacheTest {
    @Test
    func restoringAWorkspaceWithoutRootCreatesNone() { // RB-129
        setUpTree("h_tiles(1)")
        let workspace = setUpTree("floating(2)", workspace: "a")
        cacheClosedWindowIfNeeded()
        expectEqual(restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: testWindow(2)), true)
        expectEqual(workspace.existingRootTilingContainer, nil)
        expectEqual(describeTree("a"), "h_tiles() floating(2)")
    }

    @Test
    func restoreClosedWindowsCache() {
        defer { resetClosedWindowsCache() }
        let workspace = setUpTree("h_tiles(1:2 v_accordion:3(2 3)) floating(4) macos_fullscreen(5) macos_hidden(6)")
        let accordion = testWindow(2).parent
        cacheClosedWindowIfNeeded()

        // Scramble the tree. Tests find windows only in workspaces, so keep the tiling windows in another workspace
        let other = Workspace.get(byName: "other")
        for window in workspace.tilingWindows {
            window.move(to: other.rootTilingContainerCreatingIfNeeded(), at: 0, weight: .value(1))
        }
        for id: WindowId in [4, 5] {
            testWindow(id).move(to: workspace.rootTilingContainerCreatingIfNeeded(), weight: .value(1))
        }
        let orphan = TestWindow.new(id: 7, parent: workspace.rootTilingContainerCreatingIfNeeded()) // Not cached
        expectEqual(restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: orphan), false)
        expectEqual(describeTree(), "h_tiles(v_accordion() 4 5 *7) macos_hidden(6)")

        expectEqual(restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: testWindow(1)), true)
        // The orphan is bound next to the most recent window
        expectEqual(describeTree(weights: true), "h_tiles(1:2 v_accordion:3(2:1 3:1 *7:1)) floating(4 6 5)")
        // The restored workspace children are in the order of the cache, not in the canonical order of describeTree
        expectEqual(workspace.children.map { ($0 as? Container)?.kind }, [.floating, .macosFullscreen, .macosHiddenApp, .tiling])
        #expect(other.isEffectivelyEmpty)
        #expect(testWindow(2).parent !== accordion) // The tree is recreated
        expectEqual(focus.workspace, workspace)
    }
}
