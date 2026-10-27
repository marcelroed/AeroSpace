@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct DebugWindowsCommandTest {
    @Test
    func failedTargetResolutionDoesntStartRecording() async {
        // RB-34: the session used to start before the target was resolved, and stayed on after the failure.
        // No window is focused below: recording a window needs a MacWindow
        var output = await runCmd("debug-windows", windowIdEnv: 42)
        #expect(output == .fail("Invalid <window-id> 42 specified in AEROSPACE_WINDOW_ID env variable"))

        output = await runCmd("debug-windows")
        #expect(output.exitCode == 0)
        #expect(output.stdout.first?.split(separator: "\n").first == "Debug windows session has started")

        output = await runCmd("debug-windows")
        #expect(output.exitCode == 0)
        #expect(output.stdout.last == "Debug session finished\n")
    }
}
