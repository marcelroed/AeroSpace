@testable import AppBundle
import Common
import Testing

@MainActor
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
        #expect(describeTree() == spec)
    }

    @Test
    func focusesTheMarkedWindow() {
        #expect(focus.windowOrNil == nil)
        setUpTree("h_tiles(1 *2 3)")
        #expect(focus.windowOrNil?.windowId == 2)
    }

    @Test
    func roundTripWithWeights() {
        setUpTree("h_tiles(1:2 v_tiles:3(*4 5:0.5)) floating(6)")
        #expect(describeTree(weights: true) == "h_tiles(1:2 v_tiles:3(*4:1 5:0.5)) floating(6)")
        #expect(describeTree() == "h_tiles(1 v_tiles(*4 5)) floating(6)")
        #expect(testWindow(5).vWeight == 0.5)
        #expect(testWindow(5).hWeight == 3)
    }

    @Test
    func otherWorkspacesAndGlobalContainers() {
        setUpTree("h_tiles(*1)", workspace: "a")
        setUpTree("v_tiles(2) macos_minimized(3) macos_popup(4)", workspace: "b")
        #expect(focus.workspace.name == "a")
        #expect(describeTree() == "h_tiles(*1)")
        #expect(describeTree("b") == "v_tiles(2)")
        #expect(testWindow(3).parent === macosMinimizedWindowsContainer)
        #expect(testWindow(4).parent === macosPopupWindowsContainer)
    }

    @Test
    func mostRecentWindows() {
        let workspace = setUpTree("h_tiles(*1 v_tiles(2 3))")
        #expect(workspace.mostRecentWindowRecursive?.windowId == 1)
        #expect(testWindow(2).parent?.mostRecentWindowRecursive?.windowId == 3)
        // Without `*`, the most recent window of the focused workspace is focused
        setUpTree("h_tiles(4 5)", workspace: "b")
        #expect(workspace.focusWorkspace())
        #expect(describeTree() == "h_tiles(*1 v_tiles(2 3))")
        #expect(Workspace.get(byName: "b").focusWorkspace())
        #expect(describeTree() == "h_tiles(4 *5)")
    }
}
