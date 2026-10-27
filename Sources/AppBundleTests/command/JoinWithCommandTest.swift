@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct JoinWithCommandTest {
    @Test
    func joinsWithTheSibling() async {
        setUpTree("h_tiles(0 *1 2)")
        let output = await runCmd("join-with right")
        expectEqual(output, .ok)
        expectEqual(describeTree(), "h_tiles(0 v_tiles(*1 2))")
    }
}
