@testable import AppBundle
import Common
import Testing

/// Scenarios of the heavy refresh (Reconcile.swift) against FakePlatform. The call log shows what reached macOS
@Suite(.aeroSpaceGlobalState)
struct ReconcileTest {
    @Test
    func burstOfNewWindowsRunsOnWindowDetectedAfterTheBatchInListingOrder() async throws {
        fake.apps = [appA, appB]
        openWindow(3, appA)
        openWindow(1, appB)
        openWindow(2, appB)
        try readTitlesOnWindowDetected()

        await heavyRefresh()
        // One classification for the batch, then the callbacks (their matchers read the titles), in listing order
        let reads: [PlatformCall] = fake.calls.filter { $0.kind == .classify || $0.kind == .title }
        expectEqual(reads, [.classify([1, 2, 3]), .title(3), .title(1), .title(2)])
        expectEqual(describeTree(), "h_tiles(3 1 *2)")
    }

    @Test
    func windowsThatComeBackTogetherGetTheirLayoutBackWithoutOnWindowDetected() async throws {
        setUpTree("h_tiles(1 v_tiles(2 3))")
        try readTitlesOnWindowDetected()
        let closed: [WindowId: FakeWindow] = fake.windows.filter { $0.key != 1 }
        fake.windows = fake.windows.filter { $0.key == 1 }

        await heavyRefresh()
        expectEqual(describeTree(), "h_tiles(*1)")

        fake.windows.merge(closed) { $1 }
        fake.resetCalls()
        await heavyRefresh()
        expectEqual(describeTree(), "h_tiles(*1 v_tiles(2 3))")
        expectEqual(fake.calls(of: .title), [])
    }

    @Test
    func unlockingTheScreenRestoresTheWorkspaces() async {
        setUpTree("h_tiles(1 2)", workspace: "a")
        setUpTree("h_tiles(*3)", workspace: "b")
        fake.focused = 3
        await heavyRefresh()

        // Locked: macOS lists no window, and the lock screen has the focus. AeroSpace doesn't register the lock screen
        let windows = fake.windows
        fake.windows = [:]
        fake.focused = nil
        await heavyRefresh()
        #expect(world.windows.isEmpty)
        expectEqual(Workspace.all.map(\.name), ["b"])

        fake.windows = windows
        fake.focused = 3
        await heavyRefresh()
        expectEqual(describeTree("a"), "h_tiles(1 2)")
        expectEqual(describeTree("b"), "h_tiles(*3)")
        expectEqual(world.monitors.main.activeWorkspace.name, "b")
    }

    @Test
    func withoutScreensTheRefreshReadsNothing() async {
        setUpTree("h_tiles(1)")
        fake.windows[1] = nil
        openWindow(2)
        fake.monitorInfos = []

        await heavyRefresh()
        expectEqual(fake.calls, [])
        expectEqual(describeTree(), "h_tiles(*1)")
    }

    @Test
    func screensThatDisappearDuringTheReadsLeaveTheTreeAlone() async { // RB-01
        setUpTree("h_tiles(1)")
        fake.windows[1] = nil
        openWindow(2)
        fake.onRead = { if $0 == .listWindows { fake.monitorInfos = [] } }

        await heavyRefresh()
        expectEqual(describeTree(), "h_tiles(*1)")
        expectEqual(fake.calls(of: .frame), [])
    }

    @Test
    func aHungAppKeepsItsWindowsWhileTheOthersTile() async {
        fake.apps = [appA, appB]
        openWindow(1, appA)
        openWindow(2, appA)
        openWindow(3, appB)
        await heavyRefresh()

        fake.answers[appA.pid] = false
        fake.windows[2] = nil // Positive evidence comes only from an app that answers
        openWindow(4, appB)
        fake.resetCalls()
        await heavyRefresh()
        expectEqual(describeTree(), "h_tiles(1 2 3 *4)")
        // Nothing waits for the hung app: its windows aren't read
        expectEqual(fake.calls(of: .classify), [.classify([4])])
        expectEqual(fake.calls(of: .nativeFacts), [.nativeFacts([3, 4])])
        #expect(!fake.frames(of: 4).isEmpty)

        fake.answers[appA.pid] = nil
        await heavyRefresh()
        expectEqual(describeTree(), "h_tiles(1 3 *4)")
    }

    @Test
    func anOffScreenPopupStaysAPopup() async { // R2a M1
        openWindow(1)
        openWindow(2)
        fake.windows[2]?.kind = .popup // E.g. a picture-in-picture window
        await heavyRefresh()
        expectEqual(macosPopupWindowsContainer.children.map { ($0 as? Window)?.windowId }, [2])

        // Its app is hidden: no level, and AX gives the window the AXDialog subrole
        fake.windows[2]?.level = nil
        fake.windows[2]?.kind = .dialog
        await heavyRefresh()
        expectEqual(macosPopupWindowsContainer.children.map { ($0 as? Window)?.windowId }, [2])
        expectEqual(describeTree(), "h_tiles(*1)")
    }

    @Test
    func aNewWindowWhoseKindIsUnknownWaitsUntilItIsOnScreen() async throws { // R2a M1
        openWindow(1)
        fake.windows[1]?.level = nil // E.g. a Chrome window of a hidden app: only its level tells whether it's a popup
        fake.windows[1]?.kind = nil
        try readTitlesOnWindowDetected()
        await heavyRefresh()
        #expect(world.windows.isEmpty)

        fake.windows[1]?.level = .normalWindow
        fake.windows[1]?.kind = .window
        await heavyRefresh()
        expectEqual(describeTree(), "h_tiles(*1)")
        expectEqual(fake.calls(of: .title), [.title(1)]) // on-window-detected once, with the kind known
    }

    @Test
    func aRefreshPreemptedDuringTheReadsCommitsNothing() async throws {
        openWindow(1)
        try readTitlesOnWindowDetected()
        var heavy: Task<(), Never>? = nil
        fake.onRead = { if $0 == .listWindows { heavy?.cancel() } } // What a light session does

        heavy = Task.startUnstructured { await heavyRefresh() }
        await heavy?.value
        #expect(world.windows.isEmpty)
        expectEqual(fake.calls(of: .title), [])
        expectEqual(fake.calls(of: .frame), [])
    }

    @Test
    func aRefreshPreemptedDuringTheCallbacksRunsThemAllButPresentsNothing() async throws {
        openWindow(1)
        openWindow(2)
        try readTitlesOnWindowDetected()
        var heavy: Task<(), Never>? = nil
        var isCancelledInCallbacks: [Bool] = []
        fake.onRead = { call in
            guard call.kind == .title else { return }
            if call == .title(1) { heavy?.cancel() } // What a light session does
            isCancelledInCallbacks.append(Task.isCancelled)
        }

        heavy = Task.startUnstructured { await heavyRefresh() }
        await heavy?.value
        expectEqual(fake.calls(of: .title), [.title(1), .title(2)])
        expectEqual(isCancelledInCallbacks, [false, false]) // Shielded: the callbacks' commands don't see the cancellation
        expectEqual(fake.calls(of: .frame), [])
        expectEqual(describeTree(), "h_tiles(1 *2)")
    }

    @Test
    func aLightSessionRegistersTheNewFocusedWindowBeforeItsBody() async throws {
        setUpTree("h_tiles(*1)")
        try readTitlesOnWindowDetected()
        openWindow(2)
        fake.focused = 2

        let focusedInBody = try await world.sessions.light(.hotkeyBinding, .forceRun) { focus.windowOrNil?.windowId }
        world.sessions.cancelHeavy() // The heavy refresh that the session scheduled. It hasn't started: the test didn't suspend
        expectEqual(focusedInBody, 2)
        expectEqual(fake.calls(of: .title), [.title(2)]) // Its on-window-detected callbacks ran
    }

    @Test
    func aStaleNewFocusedWindowDoesntTakeTheFocusBack() async throws { // R2b M1
        setUpTree("h_tiles(*1 3)")
        fake.focused = 1
        await heavyRefresh()
        try readTitlesOnWindowDetected()
        let (gate2, gate4) = (Gate(), Gate())
        fake.beforeTitle = { id in await (id == 2 ? gate2 : gate4).wait() }

        openWindow(2)
        fake.focused = 2
        let a = Task.startUnstructured { await Reconcile.heavy(.ax("A")) }
        await gate2.untilWaiting() // A has registered 2, the new focused window, and runs its callbacks
        fake.focused = 3 // The user clicks 3
        openWindow(4)
        a.cancel()
        let b = Task.startUnstructured { await Reconcile.heavy(.ax("B")) }
        await gate4.untilWaiting() // B has taken focus 3 from macOS
        expectEqual(focus.windowOrNil?.windowId, 3)

        gate2.open()
        await a.value
        gate4.open()
        await b.value
        expectEqual(focus.windowOrNil?.windowId, 3)
        expectEqual(fake.focused, 3)
    }

    @Test
    func focusCallbacksRunInTheOrderOfTheFocusChanges() async throws { // R2b M2
        setUpTree("h_tiles(*1)", workspace: "a")
        setUpTree("h_tiles(3)", workspace: "b")
        fake.focused = 1
        await heavyRefresh()
        world.config.onFocusChanged = .cmd(LogFocusedWorkspace())
        try readTitlesOnWindowDetected()
        let gate = Gate()
        fake.beforeTitle = { _ in await gate.wait() }

        fake.focused = 3 // The user focuses workspace b, and a background window opens
        openWindow(2)
        let heavy = Task.startUnstructured { await heavyRefresh() }
        await gate.untilWaiting() // The refresh has recorded the change to b and runs on-window-detected
        _ = try await world.sessions.light(.hotkeyBinding, .forceRun) { await runCmd("workspace c") }
        world.sessions.cancelHeavy()
        gate.open()
        await heavy.value
        expectEqual(focusedWorkspaceLog, ["b", "c"])
    }

    @Test
    func debugWindowsRecordsTheWindowThatALightSessionRegistered() async throws { // R2b L2
        setUpTree("h_tiles(*1)")
        fake.focused = 1
        _ = await runCmd("debug-windows") // Start recording
        openWindow(2)
        fake.focused = 2

        _ = try await world.sessions.light(.hotkeyBinding, .forceRun) {}
        world.sessions.cancelHeavy() // The next heavy refresh doesn't see 2 as new
        let output = await runCmd("debug-windows") // Finish recording
        let dumpLines = output.stdout.joined().split(separator: "\n").filter { $0.contains(" ||| ") }
        let dumped = Set(dumpLines.compactMap { $0.split(separator: " ||| ").first })
        expectEqual(dumped, ["\(testApp.bundleId ?? "").1", "\(testApp.bundleId ?? "").2"])
    }

    @Test
    func theRefreshAfterTheStartupTilesAWindowThatOpenedMeanwhile() async throws { // RB-141
        fake.monitorInfos = [testMonitor, rightTestMonitor]
        openWindow(1)
        fake.focused = 1

        try await world.sessions.startup {
            // An app opens a window on the right monitor during the startup
            fake.windows[2] = FakeWindow(app: testApp, rect: Rect(topLeftX: 2000, topLeftY: 100, width: 800, height: 600), title: "Window 2")
        }
        for _ in 0 ..< 100 where fake.calls(of: .frame, 2).isEmpty { await Task.yield() } // Let the heavy refresh run
        expectEqual(Window.get(byId: 2)?.nodeWorkspace?.name, focus.workspace.name) // Registered as a new window
        #expect(!fake.calls(of: .frame, 2).isEmpty) // and laid out
    }

    @Test
    func focusFollowsMouseKeepsTheScheduledHeavyRefresh() async throws {
        setUpTree("h_tiles(*1)")
        openWindow(2)

        world.sessions.scheduleHeavy(.ax("test"))
        try await world.sessions.light(.focusFollowsMouse, .forceRun) {}
        for _ in 0 ..< 100 where Window.get(byId: 2) == nil { await Task.yield() } // Let the heavy refresh run
        expectEqual(describeTree(), "h_tiles(*1 2)")
    }
}

private let appA = AppInfo(pid: 1, bundleId: "test.a", name: "A", execPath: nil, bundlePath: nil)
private let appB = AppInfo(pid: 2, bundleId: "test.b", name: "B", execPath: nil, bundlePath: nil)

/// The on-focus-changed callback of focusCallbacksRunInTheOrderOfTheFocusChanges: the focused workspace it sees
private var focusedWorkspaceLog: [String] = []

private struct LogFocusedWorkspace: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = ["log-focused-workspace"]

    func run(_ cx: CmdContext) async throws(CmdFail) {
        focusedWorkspaceLog.append(try cx.target().workspace.name)
    }
}

/// A window that macOS shows and AeroSpace hasn't registered yet
private func openWindow(_ id: WindowId, _ app: AppInfo = testApp) {
    fake.windows[id] = FakeWindow(app: app, rect: nil, title: "Window \(id)")
}

private func heavyRefresh() async {
    await Reconcile.heavy(.ax("test"))
}

/// An on-window-detected callback whose matcher reads the window's title: the title reads in the call log show which
/// windows got their callbacks, in which order
private func readTitlesOnWindowDetected() throws {
    let matcher = LegacyWindowDetectedCallbackMatcher(windowTitleRegexSubstring: try CaseInsensitiveRegex("window"))
    world.config.onWindowDetected = [WindowDetectedCallback(matcher: .legacy(matcher), run: .empty)]
}
