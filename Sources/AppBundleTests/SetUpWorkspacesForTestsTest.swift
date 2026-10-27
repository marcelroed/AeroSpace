@testable import AppBundle
import Common
import Testing

/// The state a test leaves behind must not reach the next test. RB-61
@MainActor
@Suite(.aeroSpaceGlobalState)
struct SetUpWorkspacesForTestsTest {
    @Test
    func forgetsThePreviousFocus() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())
        await checkOnFocusChangedCallbacks_nonCancellable()
        #expect(Workspace.get(byName: "b").focusWorkspace())
        await checkOnFocusChangedCallbacks_nonCancellable()
        #expect(prevFocus?.workspace.name == "a")

        setUpWorkspacesForTests() // What the next test starts with
        #expect(prevFocus == nil)

        #expect(Workspace.get(byName: "c").focusWorkspace())
        await checkOnFocusChangedCallbacks_nonCancellable()
        #expect(prevFocus?.workspace.name == "setUpWorkspacesForTests") // Not "b" of the previous test
        #expect(prevFocusedWorkspace?.name == "setUpWorkspacesForTests")
    }

    @Test
    func startsFromAnEmptyWorld() {
        setUpTree("h_tiles(1) floating(2) macos_minimized(3) macos_popup(4)", workspace: "a")

        setUpWorkspacesForTests() // What the next test starts with
        #expect(Workspace.all.map(\.name) == ["setUpWorkspacesForTests"])
        #expect(macosMinimizedWindowsContainer.children.isEmpty)
        #expect(macosPopupWindowsContainer.children.isEmpty)
        #expect(Window.get(byId: 1) == nil)
    }

    @Test
    func forgetsTheLastKnownNativeFocusedWindow() {
        world.focusStore.lastKnownNativeFocusedWindowId = 1

        setUpWorkspacesForTests() // What the next test starts with
        #expect(world.focusStore.lastKnownNativeFocusedWindowId == nil)
    }
}
