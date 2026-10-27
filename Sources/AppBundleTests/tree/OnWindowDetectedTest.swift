@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct OnWindowDetectedTest {
    @Test
    func matcherCommandReceivesTheDetectedWindowId() async {
        setUpTree("h_tiles(*1 2)")
        let callback = WindowDetectedCallback(matcher: .command(parseCommand("test %{window-id} = 2").cmdOrDie), run: .empty)
        #expect(await callback.matches(testWindow(2)))
        #expect(await !callback.matches(testWindow(1)))
    }

    @Test
    func runCommandReceivesTheDetectedWindowIdInEnv() async {
        setUpTree("h_tiles(*1 2)", workspace: "a")
        config.onWindowDetected = [
            WindowDetectedCallback(matcher: .command(.empty), run: parseCommand("move-node-to-workspace b").cmdOrDie), // matches every window
        ]
        await runOnWindowDetected(ifConventional: testWindow(2)) // todo: tryOnWindowDetected must not be called manually in tests
        #expect(describeTree("a") == "h_tiles(*1)")
        #expect(describeTree("b") == "h_tiles(2)")
    }
}
