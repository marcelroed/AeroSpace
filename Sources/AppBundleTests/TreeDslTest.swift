@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct TreeDslTest {
    @Test(arguments: [
        "h_tiles()",
        "v_accordion(*1)",
        "h_tiles(1 *2 v_accordion(3 4))",
        "v_tiles(1 h_tiles(h_accordion(2 *3) 4)) floating(5 6) macos_fullscreen(7) macos_hidden(8)",
        "h_tiles() floating(*1)",
        "h_tiles(1) macos_hidden(*2)",
    ])
    func roundTrip(spec: String) {
        setUpTree(spec)
        expectEqual(describeTree(), spec)
    }

    @Test
    func focusesTheMarkedWindow() {
        expectEqual(focus.windowOrNil, nil)
        setUpTree("h_tiles(1 *2 3)")
        expectEqual(focus.windowOrNil?.windowId, 2)
    }

    @Test
    func roundTripWithWeights() {
        setUpTree("h_tiles(1:2 v_tiles:3(*4 5:0.5)) floating(6)")
        expectEqual(describeTree(weights: true), "h_tiles(1:2 v_tiles:3(*4:1 5:0.5)) floating(6)")
        expectEqual(describeTree(), "h_tiles(1 v_tiles(*4 5)) floating(6)")
        expectEqual(testWindow(5).vWeight, 0.5)
        expectEqual(testWindow(5).hWeight, 3)
    }

    @Test
    func otherWorkspacesAndGlobalContainers() {
        setUpTree("h_tiles(*1)", workspace: "a")
        setUpTree("v_tiles(2) macos_minimized(3) macos_popup(4)", workspace: "b")
        expectEqual(focus.workspace.name, "a")
        expectEqual(describeTree(), "h_tiles(*1)")
        expectEqual(describeTree("b"), "v_tiles(2)")
        #expect(testWindow(3).parent === macosMinimizedWindowsContainer)
        #expect(testWindow(4).parent === macosPopupWindowsContainer)
    }

    @Test
    func mostRecentWindows() {
        let workspace = setUpTree("h_tiles(*1 v_tiles(2 3))")
        expectEqual(workspace.mostRecentWindowRecursive?.windowId, 1)
        expectEqual(testWindow(2).parent?.mostRecentWindowRecursive?.windowId, 3)
        // Without `*`, the most recent window of the focused workspace is focused
        setUpTree("h_tiles(4 5)", workspace: "b")
        #expect(workspace.focusWorkspace())
        expectEqual(describeTree(), "h_tiles(*1 v_tiles(2 3))")
        #expect(Workspace.get(byName: "b").focusWorkspace())
        expectEqual(describeTree(), "h_tiles(4 *5)")
    }
}
