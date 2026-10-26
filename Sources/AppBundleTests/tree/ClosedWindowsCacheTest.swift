@testable import AppBundle
import AppKit
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct ClosedWindowsCacheTest: AeroSpaceTestSuite {
    @Test
    func testRestoreClosedWindowsCache() async throws {
        defer { resetClosedWindowsCache() }
        let workspace = Workspace.get(byName: name)
        assertTrue(workspace.focusWorkspace())
        var accordion: TilingContainer! = nil
        workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0, adaptiveWeight: 2)
            accordion = TilingContainer(parent: $0, adaptiveWeight: 3, .v, .accordion, index: INDEX_BIND_LAST).apply {
                TestWindow.new(id: 2, parent: $0)
                TestWindow.new(id: 3, parent: $0)
            }
        }
        TestWindow.new(id: 4, parent: workspace.floatingWindowsContainer)
        TestWindow.new(id: 5, parent: workspace.macOsNativeFullscreenWindowsContainer)
        TestWindow.new(id: 6, parent: workspace.macOsNativeHiddenAppsWindowsContainer)
        cacheClosedWindowIfNeeded()

        // Scramble the tree. Tests find windows only in workspaces, so keep the tiling windows in another workspace
        let other = Workspace.get(byName: "other")
        for window in workspace.rootTilingContainer.allLeafWindowsRecursive {
            window.bind(to: other.rootTilingContainer, adaptiveWeight: 1, index: 0)
        }
        for id: UInt32 in [4, 5] {
            Window.get(byId: id).orDie().bind(to: workspace.rootTilingContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        }
        let orphan = TestWindow.new(id: 7, parent: workspace.rootTilingContainer) // Not cached
        assertEquals(try await restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: orphan), false)
        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.v_accordion([]), .window(4), .window(5), .window(7)]))

        let window1 = Window.get(byId: 1).orDie()
        assertEquals(try await restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: window1), true)
        assertEquals(workspace.layoutDescription, .workspace([
            .floatingWindowsContainer([.window(4), .window(6), .window(5)]),
            .macosFullscreen,
            .macosHiddenAppWindow,
            .h_tiles([.window(1), .v_accordion([.window(2), .window(3), .window(7)])]), // The orphan is bound next to the MRU window
        ]))
        assertEquals(other.rootTilingContainer.children.count, 0)
        assertEquals(window1.hWeight, 2)
        assertTrue(workspace.rootTilingContainer.children[1] !== accordion) // The tree is recreated
        assertEquals(workspace.rootTilingContainer.children[1].hWeight, 3)
        assertEquals(focus.workspace, workspace)
    }
}
