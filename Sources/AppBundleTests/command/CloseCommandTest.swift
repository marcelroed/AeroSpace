@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct CloseCommandTest {
    @Test(arguments: [
        ("close", "h_tiles(*2)"),
        ("close --window-id 2", "h_tiles(*1)"),
    ] as [(String, String)])
    func closes(command: String, after: String) async {
        setUpTree("h_tiles(*1 2)")
        let output = await runCmd(command)
        expectEqual(output, .ok)
        expectEqual(describeTree(), after)
    }
}
