@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct TreeDslTest {
    /// `setUpTree` then `describeTree` gives the spec back. A row with a workspace also renders the global containers
    @Test(arguments: [
        ("h_tiles()", nil, false),
        ("v_accordion(*1)", nil, false),
        ("h_tiles(1 *2 v_accordion(3 4))", nil, false),
        ("v_tiles(1 h_tiles(h_accordion(2 *3) 4)) floating(5 6) macos_fullscreen(7) macos_hidden(8)", nil, false),
        ("h_tiles() floating(*1)", nil, false),
        ("h_tiles(1) macos_hidden(*2)", nil, false),
        ("h_tiles(1:2 v_tiles:3(*4:1 5:0.5)) floating(6)", nil, true),
        ("v_tiles(2) macos_minimized(3) macos_popup(4)", "b", false),
    ] as [(String, String?, Bool)])
    func roundTrip(spec: String, workspace: String?, weights: Bool) {
        setUpTree(spec, workspace: workspace)
        let globalContainers: [Container] = workspace == nil ? [] : [macosMinimizedWindowsContainer, macosPopupWindowsContainer]
        let parts: [String] = [describeTree(workspace, weights: weights)] + globalContainers.map { describeNode($0) }
        expectEqual(parts.joined(separator: " "), spec)
    }
}
