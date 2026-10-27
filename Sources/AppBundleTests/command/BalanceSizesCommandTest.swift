@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct BalanceSizesCommandTest {
    @Test
    func balancesTheWeights() async {
        let workspace = setUpTree("h_tiles(1:1 v_tiles:2(2:1 3:3) *4:3)")
        let output = await runCmd("balance-sizes", workspaceEnv: workspace.name)
        #expect(output == .ok)
        #expect(describeTree(weights: true) == "h_tiles(1:1 v_tiles:1(2:1 3:1) *4:1)")
    }
}
