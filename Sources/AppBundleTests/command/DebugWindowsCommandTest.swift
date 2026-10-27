@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct DebugWindowsCommandTest: AeroSpaceTestSuite {
    @Test
    func testFailedTargetResolutionDoesntStartRecording() async {
        // RB-34: the session used to start before the target was resolved, and stayed on after the failure.
        // No window is focused below: recording a window needs a MacWindow
        assertEquals(
            await parseCommand("debug-windows").cmdOrDie.run(.defaultEnv.withWindowId(42), .emptyStdin),
            CmdResult(stdout: [], stderr: ["Invalid <window-id> 42 specified in AEROSPACE_WINDOW_ID env variable"], exitCode: .fail),
        )

        let started = await parseCommand("debug-windows").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(started.exitCode, .succ)
        assertEquals(started.stdout.first?.split(separator: "\n").first, "Debug windows session has started")

        let finished = await parseCommand("debug-windows").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(finished.exitCode, .succ)
        assertEquals(finished.stdout.last, "Debug session finished\n")
    }
}
