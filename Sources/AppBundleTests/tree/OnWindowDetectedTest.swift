@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct OnWindowDetectedTest {
    @Test
    func matcherCommandReceivesTheDetectedWindowId() async {
        setUpTree("h_tiles(*1 2)")
        let callback = WindowDetectedCallback(matcher: .command(parseCommand("test %{window-id} = 2").cmdOrDie), run: .empty)
        #expect(await callback.matches(testWindow(2), isStartup: false))
        #expect(await !callback.matches(testWindow(1), isStartup: false))
    }

    @Test
    func runCommandReceivesTheDetectedWindowIdInEnv() async {
        setUpTree("h_tiles(*1)", workspace: "a")
        world.config.onWindowDetected = [
            WindowDetectedCallback(matcher: .command(.empty), run: parseCommand("move-node-to-workspace b").cmdOrDie), // matches every window
        ]
        fake.windows[2] = FakeWindow(app: testApp, rect: nil, title: "Window 2") // A new window
        await Reconcile.heavy(.ax("test"))
        expectEqual(describeTree("a"), "h_tiles(*1)")
        expectEqual(describeTree("b"), "h_tiles(2)")
    }
}
