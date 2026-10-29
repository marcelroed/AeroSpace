@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct CloseCommandTest {
    @Test(arguments: [
        (fourWindows, "close", "h_tiles(2 v_tiles(*3)) floating(4)", false),
        (fourWindows, "close --window-id 2", "h_tiles(*1 v_tiles(3)) floating(4)", false),
        (fourWindows, "close --quit-if-last-window", "h_tiles(2 v_tiles(*3)) floating(4)", false),
        ("h_tiles(*1)", "close --quit-if-last-window", "h_tiles()", true),
        (fourWindows, "close-all-windows-but-current", "h_tiles(*1)", false),
        // The focused window stays, so the app always has another window: the app isn't quit
        (fourWindows, "close-all-windows-but-current --quit-if-last-window", "h_tiles(*1)", false),
    ] as [(String, String, String, Bool)])
    func closes(before: String, command: String, after: String, quitsTheApp: Bool) async {
        setUpTree(before)
        let output = await runCmd(command)
        expectEqual(output, .ok)
        expectEqual(describeTree(), after)
        expectEqual(fake.calls(of: .quit), quitsTheApp ? [.quit(testApp.pid)] : [])
    }
}

/// Four windows of ``testApp``
nonisolated private let fourWindows = "h_tiles(*1 2 v_tiles(3)) floating(4)"
