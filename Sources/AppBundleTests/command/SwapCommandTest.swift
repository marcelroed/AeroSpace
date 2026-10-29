@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct SwapCommandTest {
    /// Every command runs on the tree that the previous one left
    @Test(arguments: swapCases)
    func swaps(start: String, steps: [(command: String, after: String)]) async {
        let workspace = setUpTree(start)
        for (command, after) in steps {
            let output = await runCmd(command)
            expectEqual(output, .ok)
            expectEqual(describeTree(), after, "after '\(command)'")
            expectEqual(workspace.mostRecentWindowRecursive?.windowId, focus.windowOrNil?.windowId) // The focused window is the most recent one
        }
    }

    /// RB-108: with --wrap-around, a floating window traded places with a tiling window
    @Test(arguments: ["swap --wrap-around left", "swap left", "swap dfs-next"] as [String])
    func failsForAWindowThatIsntTiled(command: String) async {
        let tree: String = "h_tiles(1 2) floating(*3)"
        setUpTree(tree)
        let output = await runCmd(command)
        expectEqual(output, .fail("Can't swap a window that isn't tiled"))
        expectEqual(describeTree(), tree)
    }
}

/// Explicitly typed: inferring the type of the nested literal took about a second of type checking
nonisolated private let swapCases: [(start: String, steps: [(command: String, after: String)])] = [
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
]
