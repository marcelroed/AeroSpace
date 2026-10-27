@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct SwapCommandTest {
    /// Every command runs on the tree that the previous one left
    @Test(arguments: [
        ("h_tiles(v_tiles(*1 2) 3)", [
            ("swap right", "h_tiles(v_tiles(3 2) *1)"),
            ("swap left", "h_tiles(v_tiles(*1 2) 3)"),
            ("swap down", "h_tiles(v_tiles(2 *1) 3)"),
            ("swap up", "h_tiles(v_tiles(*1 2) 3)"),
        ]),
        ("h_tiles(v_tiles(*1 2) 3)", [
            ("swap dfs-next", "h_tiles(v_tiles(2 *1) 3)"),
            ("swap dfs-next", "h_tiles(v_tiles(2 3) *1)"),
            ("swap dfs-prev", "h_tiles(v_tiles(2 *1) 3)"),
            ("swap dfs-prev", "h_tiles(v_tiles(*1 2) 3)"),
        ]),
        ("h_tiles(*1 2 3)", [
            ("swap --wrap-around left", "h_tiles(3 2 *1)"),
            ("swap --wrap-around right", "h_tiles(*1 2 3)"),
        ]),
        ("h_tiles(*1 2 3)", [
            ("swap --wrap-around dfs-prev", "h_tiles(3 2 *1)"),
            ("swap --wrap-around dfs-next", "h_tiles(*1 2 3)"),
        ]),
        ("h_tiles(1 *2 3)", [
            ("swap --swap-focus right", "h_tiles(1 *3 2)"),
        ]),
    ])
    func swaps(start: String, steps: [(command: String, after: String)]) async {
        let workspace = setUpTree(start)
        for (command, after) in steps {
            let output = await runCmd(command)
            #expect(output == .ok)
            #expect(describeTree() == after, "after '\(command)'")
            #expect(workspace.mostRecentWindowRecursive?.windowId == focus.windowOrNil?.windowId) // The focused window is the most recent one
        }
    }
}
