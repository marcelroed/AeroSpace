@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct FlattenWorkspaceTreeCommandTest {
    @Test
    func flattens() async {
        let workspace = setUpTree("h_tiles(1 v_tiles(2 h_tiles(*3))) floating(4)")
        let output = await runCmd("flatten-workspace-tree")
        #expect(output == .ok)
        workspace.normalizeContainers()
        #expect(describeTree() == "h_tiles(1 2 *3) floating(4)") // Floating windows stay floating
    }
}
