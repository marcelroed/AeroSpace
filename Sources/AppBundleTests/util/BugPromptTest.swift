import Common
import Foundation
import Testing

@Suite
struct BugPromptTest {
    // RB-47: AppKit doesn't document NSScreen as thread-safe, and the dying thread is often an AX thread
    @Test
    func testBugPromptReadsScreensOnlyOnMainThread() async {
        let prompt = await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            Thread { cont.resume(returning: bugPrompt()) }.start()
        }
        assertTrue(prompt.contains("Monitor count: n/a (not main thread)\n"))
        assertTrue(prompt.contains("Displays have separate spaces: n/a (not main thread)\n"))
    }

    @MainActor
    @Test
    func testBugPromptReadsScreensOnMainThread() {
        assertFalse(bugPrompt().contains("n/a (not main thread)"))
    }
}
