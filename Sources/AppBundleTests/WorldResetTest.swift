@testable import AppBundle
import Common
import Foundation
import Testing

/// What a test leaves behind must not reach the next test (RB-61). ``World/reset(platform:)`` copies every property of a
/// fresh world by hand, so this test changes every property first, and fails for a property that it doesn't change
@Suite(.aeroSpaceGlobalState)
struct WorldResetTest {
    @Test
    func resetForgetsEverything() async {
        await changeEveryProperty()
        let (ui, sessions) = (world.ui, world.sessions)
        let platform = FakePlatform()
        let fresh = propertyDumps(of: World(sharingUiAndSessionsOf: world, platform: platform))
        let changed = propertyDumps(of: world)
        for (name, value) in fresh where changed[name] == value {
            Issue.record("The test doesn't change world.\(name): change it in changeEveryProperty()")
        }

        world.reset(platform: platform)

        let reset = propertyDumps(of: world)
        for (name, value) in fresh where reset[name] != value {
            Issue.record("World.reset doesn't reset world.\(name)")
        }
        // The scenes hold `ui` and `sessions`: they stay, without the state of the previous test
        #expect(world.ui === ui && world.sessions === sessions)
        #expect(world.ui.trayMenuModel.isEnabled)
        expectEqual(world.ui.messageModel.message, nil)
    }

    /// The tests reach macOS only through FakePlatform: a test that reaches the live platform dies, in a child process here
    @Test
    func aTestDiesAtTheLivePlatform() async {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            await MainActor.run { _ = World().platform }
        }
        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("LivePlatform (a test installs FakePlatform with setUpWorkspacesForTests()) would act on the user's session"))
    }
}

/// Changes the properties through the code that changes them in the app, where that's simple
private func changeEveryProperty() async {
    setUpTree("h_tiles(1) floating(2) macos_minimized(3) macos_popup(4)", workspace: "a") // The trees, the windows, the MRU clock
    updateMonitors([testMonitor, rightTestMonitor])
    #expect(Workspace.get(byName: "a").focusWorkspace())
    await checkOnFocusChangedCallbacks_nonCancellable()
    #expect(Workspace.get(byName: "b").focusWorkspace())
    await checkOnFocusChangedCallbacks_nonCancellable()
    expectEqual(prevFocus?.workspace.name, "a") // focus-back-and-forth's
    cacheClosedWindowIfNeeded()
    world.config.accordionPadding += 1
    world.configUrl = URL(filePath: "/changed.toml")
    world.activeMode = nil
    world.layoutForNextDetectedWindow = .floating
    world.mouseManipulatedWindowId = 1
    world.debugWindows = .aborted
    world.isEnabled = false
    world.ui.messageModel.message = Message(body: "From the previous test")
    _ = Workspace.all // Sorts the workspaces
}

/// The `dump` of every property but `ui` and `sessions`, which outlive the reset
private func propertyDumps(of world: World) -> [String: String] {
    var result: [String: String] = [:]
    for case let (name?, value) in Mirror(reflecting: world).children where name != "ui" && name != "sessions" {
        var text = ""
        dump(value, to: &text)
        result[name] = text
    }
    return result
}
