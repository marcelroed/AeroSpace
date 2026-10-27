@testable import AppBundle
import Common
import Testing

/// The state a test leaves behind must not reach the next test. RB-61
@Suite(.aeroSpaceGlobalState)
struct SetUpWorkspacesForTestsTest {
    @Test
    func forgetsThePreviousFocus() async {
        #expect(Workspace.get(byName: "a").focusWorkspace())
        await checkOnFocusChangedCallbacks_nonCancellable()
        #expect(Workspace.get(byName: "b").focusWorkspace())
        await checkOnFocusChangedCallbacks_nonCancellable()
        expectEqual(prevFocus?.workspace.name, "a")

        setUpWorkspacesForTests() // What the next test starts with
        expectEqual(prevFocus, nil)

        #expect(Workspace.get(byName: "c").focusWorkspace())
        await checkOnFocusChangedCallbacks_nonCancellable()
        expectEqual(prevFocus?.workspace.name, "setUpWorkspacesForTests") // Not "b" of the previous test
        expectEqual(prevFocusedWorkspace?.name, "setUpWorkspacesForTests")
    }

    @Test
    func startsFromAnEmptyWorld() {
        setUpTree("h_tiles(1) floating(2) macos_minimized(3) macos_popup(4)", workspace: "a")

        setUpWorkspacesForTests() // What the next test starts with
        expectEqual(Workspace.all.map(\.name), ["setUpWorkspacesForTests"])
        #expect(macosMinimizedWindowsContainer.children.isEmpty)
        #expect(macosPopupWindowsContainer.children.isEmpty)
        expectEqual(Window.get(byId: 1), nil)
    }

    @Test
    func forgetsTheLastKnownNativeFocusedWindow() {
        world.focusStore.lastKnownNativeFocusedWindowId = 1

        setUpWorkspacesForTests() // What the next test starts with
        expectEqual(world.focusStore.lastKnownNativeFocusedWindowId, nil)
    }

    /// `ui` and `sessions` outlive the reset: the scenes hold them
    @Test
    func startsEnabledWithoutAMessage() {
        world.isEnabled = false
        world.ui.messageModel.message = Message(body: "From the previous test")

        setUpWorkspacesForTests() // What the next test starts with
        #expect(world.isEnabled)
        #expect(world.ui.trayMenuModel.isEnabled)
        expectEqual(world.ui.messageModel.message, nil)
    }
}
