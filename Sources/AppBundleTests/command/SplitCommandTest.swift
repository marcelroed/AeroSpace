@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct SplitCommandTest {
    @Test(arguments: [
        ("h_tiles(*1 2)", "split vertical", "h_tiles(v_tiles(*1) 2)"),
        ("h_tiles(*1 2)", "split opposite", "h_tiles(v_tiles(*1) 2)"),
        // A single child container changes its orientation instead
        ("h_tiles(v_tiles(*1) 2)", "split horizontal", "h_tiles(h_tiles(*1) 2)"),
        ("h_tiles(v_tiles(*1) 2)", "split opposite", "h_tiles(h_tiles(*1) 2)"),
    ])
    func splits(before: String, command: String, after: String) async {
        setUpTree(before)
        let output = await runCmd(command)
        #expect(output == .ok)
        #expect(describeTree() == after)
    }
}
