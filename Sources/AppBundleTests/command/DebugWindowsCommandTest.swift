@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct DebugWindowsCommandTest {
    @Test
    func failedTargetResolutionDoesntStartRecording() async {
        // RB-34: the session used to start before the target was resolved, and stayed on after the failure.
        // No window is focused below: the recording dumps none
        var output = await runCmd("debug-windows", windowIdEnv: 42)
        expectEqual(output, .fail("Invalid <window-id> 42 specified in AEROSPACE_WINDOW_ID env variable"))

        output = await runCmd("debug-windows")
        expectEqual(output.exitCode, 0)
        expectEqual(output.stdout.first?.split(separator: "\n").first, "Debug windows session has started")

        output = await runCmd("debug-windows")
        expectEqual(output.exitCode, 0)
        expectEqual(output.stdout.last, "Debug session finished\n")
    }

    @Test
    func dumpAwaitedDuringOneRecordingStaysOutOfTheNext() async {
        // RB-110: a dump that was awaited while one recording finished and the next one started went into the next one,
        // and kept that recording from dumping the window itself
        _ = await runCmd("debug-windows") // Start recording A
        let (dumpStarted, dumpStartedCont) = AsyncStream<Void>.makeStream()
        let (finishDump, finishDumpCont) = AsyncStream<Void>.makeStream()
        let dumpDuringA = Task.startUnstructured {
            await recordDebugWindow(1) {
                dumpStartedCont.finish()
                for await _ in finishDump {}
                return "window 1 dumped during A"
            }
        }
        for await _ in dumpStarted {}
        _ = await runCmd("debug-windows") // Finish A
        _ = await runCmd("debug-windows") // Start recording B
        finishDumpCont.finish()
        await dumpDuringA.value
        await recordDebugWindow(1) { "window 1 dumped during B" }

        let output = await runCmd("debug-windows") // Finish B
        expectEqual(output.stdout.first, "window 1 dumped during B")
    }
}
