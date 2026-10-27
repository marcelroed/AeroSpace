@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct CloseCommandTest {
    @Test(arguments: [
        ("close", "h_tiles(2 v_tiles(*3)) floating(4)"),
        ("close --window-id 2", "h_tiles(*1 v_tiles(3)) floating(4)"),
        ("close-all-windows-but-current", "h_tiles(*1)"),
        // The focused window stays, so the app always has another window: the app isn't quit
        ("close-all-windows-but-current --quit-if-last-window", "h_tiles(*1)"),
    ] as [(String, String)])
    func closes(command: String, after: String) async {
        setUpTree("h_tiles(*1 2 v_tiles(3)) floating(4)")
        let output = await runCmd(command)
        expectEqual(output, .ok)
        expectEqual(describeTree(), after)
        expectEqual(fake.calls(of: .quit), [])
    }
}
