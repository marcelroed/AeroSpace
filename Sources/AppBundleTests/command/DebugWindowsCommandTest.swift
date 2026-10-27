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
        await assertRun(
            "debug-windows",
            env: .defaultEnv.withWindowId(42),
            exitCode: 2,
            stdout: [],
            stderr: ["Invalid <window-id> 42 specified in AEROSPACE_WINDOW_ID env variable"],
        )

        let started = await assertRun("debug-windows", exitCode: 0)
        assertEquals(started.stdout.first?.split(separator: "\n").first, "Debug windows session has started")

        let finished = await assertRun("debug-windows", exitCode: 0)
        assertEquals(finished.stdout.last, "Debug session finished\n")
    }
}
