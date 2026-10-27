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
    func aHungAppDoesntHoldTheRefreshAndItsWindowsComeWhenItAnswers() async { // RB-144
        fake.apps = [appA, appB]
        openWindow(1, appA)
        await heavyRefresh()
        fake.listingDeadlines = ListingDeadlines(minDeadline: .milliseconds(1), maxDeadline: .seconds(1))
        let hang = Gate()
        var listingsOfA = 0
        fake.beforeListing = { app in
            guard app == appA else { return }
            listingsOfA += 1
            await hang.wait()
        }
        openWindow(2, appA)
        openWindow(3, appB)

        await heavyRefresh() // A misses its deadline
        expectEqual(Set(world.windows.keys), [1, 3])
        await heavyRefresh() // A's listing still runs: A isn't asked again
        expectEqual(listingsOfA, 1)
        expectEqual(Set(world.windows.keys), [1, 3])

        hang.open() // A answers late. A heavy refresh lists it again
        for _ in 0 ..< 100 where Window.get(byId: 2) == nil { await Task.yield() }
        expectEqual(listingsOfA, 2)
        expectEqual(Set(world.windows.keys), [1, 2, 3])
    }

    @Test
    func theStartupWaitsForEveryApp() async { // RB-144
        fake.apps = [appA, appB]
        openWindow(1, appA)
        openWindow(2, appB)
        fake.listingDeadlines = ListingDeadlines(minDeadline: .milliseconds(1), maxDeadline: .seconds(1)) { _ in } // Passed at once
        let slowness = Gate()
        fake.beforeListing = { app in if app == appA { await slowness.wait() } }

        var isDone = false
        let startup = Task.startUnstructured {
            await Reconcile.heavy(.startup, isStartup: true)
            isDone = true
        }
        await slowness.untilWaiting()
        for _ in 0 ..< 100 { await Task.yield() }
        #expect(!isDone)
        expectEqual(fake.calls(of: .listWindows), [])
        slowness.open()
        await startup.value
        expectEqual(Set(world.windows.keys), [1, 2])
    }

    @Test
    func twoLateAppsGetTheirWindowsEachWhenItAnswers() async {
        fake.apps = [appA, appB]
        await heavyRefresh()
        var deadline = Gate()
        fake.listingDeadlines = ListingDeadlines(minDeadline: .milliseconds(1), maxDeadline: .seconds(1)) { _ in
            await deadline.wait()
        }
        let (hangA, hangB) = (Gate(), Gate())
        var listings: [String] = []
        fake.beforeListing = { app in
            listings.append(app == appA ? "A" : "B")
            await (app == appA ? hangA : hangB).wait()
        }
        openWindow(1, appA)
        openWindow(2, appB)

        let refresh = Task.startUnstructured { await heavyRefresh() }
        await hangA.untilWaiting()
        await hangB.untilWaiting() // Both apps are listed at once
        deadline.open() // Both miss it
        await refresh.value
        expectEqual(Set(world.windows.keys), [])
        deadline = Gate()

        hangB.open() // B answers late: a heavy refresh lists it again, and doesn't ask A, whose listing still runs
        for _ in 0 ..< 100 where Window.get(byId: 2) == nil { await Task.yield() }
        expectEqual(Set(world.windows.keys), [2])
        expectEqual(listings, ["A", "B", "B"])

        hangA.open() // A answers late: a heavy refresh lists both apps
        for _ in 0 ..< 100 where Window.get(byId: 1) == nil { await Task.yield() }
        expectEqual(Set(world.windows.keys), [1, 2])
        expectEqual(listings, ["A", "B", "B", "A", "B"])
        deadline.open() // The deadlines of the listings that answered in time
    }

    @Test
    func twoAppsSlowerThanTheCapGetTheirWindows() async {
        fake.apps = [appA, appB]
        await heavyRefresh()
        // Both apps answer slower than the cap: a deadline up to the cap passes at once. A longer deadline (after a late
        // answer) passes only at the end, so a listing with it answers in time
        let longDeadline = Gate()
        let deadlines = ListingDeadlines(minDeadline: .nanoseconds(1), maxDeadline: .nanoseconds(1)) { deadline in
            if deadline > .nanoseconds(1) { await longDeadline.wait() }
        }
        fake.listingDeadlines = deadlines
        let (answersOfA, answersOfB) = ((0 ..< 4).map { _ in Gate() }, (0 ..< 4).map { _ in Gate() })
        var listings: [String] = []
        fake.beforeListing = { app in
            let name = app == appA ? "A" : "B"
            let answers = app == appA ? answersOfA : answersOfB
            let index = listings.count { $0 == name }
            listings.append(name)
            if index < answers.count { await answers[index].wait() }
        }
        openWindow(1, appA)
        openWindow(2, appB)

        world.sessions.scheduleHeavy(.ax("test")) // Both apps miss the deadline
        await answersOfA[0].untilWaiting()
        await answersOfB[0].untilWaiting()
        for _ in 0 ..< 100 where !world.sessions.isHeavyIdle { await Task.yield() }
        expectEqual(Set(world.windows.keys), [])

        answersOfA[0].open() // A answers late, and a refresh lists it with the longer deadline. B's listing still runs
        await answersOfA[1].untilWaiting()
        answersOfB[0].open() // B answers late. Its refresh replaces A's before A answers, and lists both apps
        await answersOfA[2].untilWaiting()
        await answersOfB[1].untilWaiting()
        #expect(deadlines.deadline(appA.pid) > .nanoseconds(1)) // The cancelled refresh didn't use up A's longer deadline

        answersOfA[2].open()
        answersOfB[1].open()
        for _ in 0 ..< 100 where !world.sessions.isHeavyIdle { await Task.yield() }
        expectEqual(Set(world.windows.keys), [1, 2])
        expectEqual(listings, ["A", "B", "A", "A", "B"])
        expectEqual(deadlines.deadline(appA.pid), .nanoseconds(1)) // Each longer deadline was used once
        expectEqual(deadlines.deadline(appB.pid), .nanoseconds(1))

        for gate in answersOfA + answersOfB { gate.open() } // The replaced refresh's listing of A answers: nothing to do
        longDeadline.open()
        for _ in 0 ..< 100 { await Task.yield() }
        #expect(world.sessions.isHeavyIdle)
        expectEqual(listings.count, 5)
    }

    @Test
    func anOffScreenPopupStaysAPopup() async {
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
    func aNewWindowWhoseKindIsUnknownWaitsUntilItIsOnScreen() async throws {
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
    func aNewWindowWhoseKindIsUnknownCostsNoReadsButItsClassification() async throws {
        openWindow(1)
        fake.windows[1]?.level = nil // E.g. a minimized Chrome window: it stays unregistered while it's minimized
        fake.windows[1]?.kind = nil
        fake.focused = 1
        _ = await runCmd("debug-windows") // Start recording
        fake.resetCalls()

        await heavyRefresh()
        #expect(world.windows.isEmpty)
        expectEqual(fake.calls(of: .classify), [.classify([1])])
        expectEqual(fake.calls(of: .nativeFacts), [.nativeFacts([])])
        expectEqual(fake.calls(of: .debugInfo), [])
        _ = try await world.sessions.light(.hotkeyBinding, .forceRun) {}
        world.sessions.cancelHeavy()
        expectEqual(fake.calls(of: .debugInfo), [])
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
        var (framesOfTheRefresh, isAnotherRefreshScheduled) = ([PlatformCall](), false)
        var isCancelledInCallbacks: [Bool] = []
        fake.onRead = { call in
            guard call.kind == .title else { return }
            if call == .title(1) { heavy?.cancel() } // What a light session does
            isCancelledInCallbacks.append(Task.isCancelled)
        }

        heavy = Task.startUnstructured {
            await heavyRefresh()
            (framesOfTheRefresh, isAnotherRefreshScheduled) = (fake.calls(of: .frame), !world.sessions.isHeavyIdle)
            world.sessions.cancelHeavy()
        }
        await heavy?.value
        expectEqual(fake.calls(of: .title), [.title(1), .title(2)])
        expectEqual(isCancelledInCallbacks, [false, false]) // Shielded: the callbacks' commands don't see the cancellation
        expectEqual(framesOfTheRefresh, [])
        #expect(isAnotherRefreshScheduled) // It presents what the callbacks did
        expectEqual(describeTree(), "h_tiles(1 *2)")
    }

    @Test
    func aCallbackThatMovesAWindowAfterThePreemptionIsPresented() async throws {
        setUpTree("h_tiles(*1)")
        fake.focused = 1
        await heavyRefresh()
        let matcher = LegacyWindowDetectedCallbackMatcher(windowTitleRegexSubstring: try CaseInsensitiveRegex("window"))
        let run = parseCommand("move-node-to-workspace x").cmdOrDie
        world.config.onWindowDetected = [WindowDetectedCallback(matcher: .legacy(matcher), run: run)]
        let gate = Gate()
        fake.beforeTitle = { _ in await gate.wait() }

        openWindow(2)
        world.sessions.scheduleHeavy(.ax("test"))
        await gate.untilWaiting() // The refresh has registered 2 and runs its on-window-detected
        _ = try await world.sessions.light(.hotkeyBinding, .forceRun) {} // Cancels the refresh, presents, schedules another
        for _ in 0 ..< 100 where !world.sessions.isHeavyIdle { await Task.yield() }
        #expect(world.sessions.isHeavyIdle) // The light session and its heavy refresh have presented 2 on the focused workspace
        expectEqual(fake.calls(of: .park), [])

        gate.open() // The callback moves 2 to workspace x
        for _ in 0 ..< 100 where fake.calls(of: .park).isEmpty { await Task.yield() }
        expectEqual(fake.calls(of: .park).map(\.windowId), [2])
    }

    /// An app moves its window while a heavy refresh is held in its listing. The refresh's P4 reads the window after the
    /// event and moves it back, so the event doesn't restart the refresh, unless AeroSpace doesn't know the window (the
    /// listing may have missed it)
    @Test(arguments: [(.moved(windowId: 1), 1), (.resized(windowId: 1), 1), (.moved(windowId: 3), 2)] as [(AxEvent, Int)])
    func anAppsMoveDuringAHeavyRefreshRestartsItOnlyForAnUnknownWindow(event: AxEvent, expectedListings: Int) async {
        setUpTree("h_tiles(*1 2)")
        testWindow(1).rect = rect(0, 0, 100, 100)
        fake.focused = 1
        await heavyRefresh()
        let tile = testWindow(1).rect
        let gate = Gate()
        var listings = 0
        fake.beforeListing = { _ in
            listings += 1
            await gate.wait()
        }
        world.sessions.scheduleHeavy(.ax("test"))
        await gate.untilWaiting()

        testWindow(1).rect = rect(100, 100, 500, 500)
        await world.sessions.onAxEvent(event)
        gate.open()
        for _ in 0 ..< 100 where !world.sessions.isHeavyIdle { await Task.yield() }
        expectEqual(listings, expectedListings)
        expectEqual(testWindow(1).rect, tile)
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

    /// 2 opens with the native focus, and its refresh A runs its callbacks. Meanwhile, the user clicks `clicked` (another
    /// window, or 1, which had the focus before 2), and the refresh B that replaces A takes that focus. A's 2 doesn't take
    /// it back
    @Test(arguments: [3, 1] as [WindowId])
    func aStaleNewFocusedWindowDoesntTakeTheFocusBack(clicked: WindowId) async throws {
        setUpTree("h_tiles(*1 3)")
        fake.focused = 1
        await heavyRefresh()
        try readTitlesOnWindowDetected()
        let (gate2, gate4) = (Gate(), Gate())
        fake.beforeTitle = { id in await (id == 2 ? gate2 : gate4).wait() }

        openWindow(2)
        fake.focused = 2
        world.sessions.scheduleHeavy(.ax("A"))
        await gate2.untilWaiting() // A has registered 2, the new focused window, and runs its callbacks
        fake.focused = clicked
        openWindow(4)
        world.sessions.scheduleHeavy(.ax("B")) // Replaces A, whose callbacks go on
        await gate4.untilWaiting() // B has taken the focus from macOS
        expectEqual(focus.windowOrNil?.windowId, clicked)

        gate2.open()
        for _ in 0 ..< 100 { await Task.yield() } // A ends its callbacks
        expectEqual(focus.windowOrNil?.windowId, clicked)
        gate4.open()
        for _ in 0 ..< 100 where !world.sessions.isHeavyIdle { await Task.yield() }
        #expect(world.sessions.isHeavyIdle)
        expectEqual(focus.windowOrNil?.windowId, clicked)
        expectEqual(fake.focused, clicked)
    }

    @Test
    func aStaleNewFocusedWindowDoesntTakeTheFocusBackAfterALightSession() async throws {
        setUpTree("h_tiles(*1 3)")
        fake.focused = 1
        await heavyRefresh()
        logFocusOnFocusChanged(.window)
        try readTitlesOnWindowDetected()
        let gate = Gate()
        fake.beforeTitle = { _ in await gate.wait() }

        openWindow(2)
        fake.focused = 2
        world.sessions.scheduleHeavy(.ax("A"))
        await gate.untilWaiting() // A has registered 2, the new focused window, and runs its callbacks
        fake.focused = 1 // The user clicks back on 1 and presses a hotkey
        _ = try await world.sessions.light(.hotkeyBinding, .forceRun) {}
        world.sessions.cancelHeavy()
        gate.open()
        for _ in 0 ..< 100 { await Task.yield() } // A ends its callbacks
        expectEqual(focus.windowOrNil?.windowId, 1)
        expectEqual(fake.focused, 1)
        expectEqual(focusLog, []) // The focus didn't go to 2 and back
    }

    @Test
    func aLightSessionsNewFocusedWindowDoesntTakeTheFocusBackFromThePreviousWindow() async throws {
        setUpTree("h_tiles(*1 3)")
        fake.focused = 1
        await heavyRefresh()
        logFocusOnFocusChanged(.window)
        try readTitlesOnWindowDetected()
        let gate = Gate()
        fake.beforeTitle = { _ in await gate.wait() }

        openWindow(2)
        fake.focused = 2
        var focusedInBody: WindowId? = nil
        let first = Task.startUnstructured {
            _ = try? await world.sessions.light(.hotkeyBinding, .forceRun) { focusedInBody = focus.windowOrNil?.windowId }
        }
        await gate.untilWaiting() // The session has registered 2, the new focused window, and runs its callbacks
        fake.focused = 1 // The user clicks back on 1 and presses another hotkey
        _ = try await world.sessions.light(.hotkeyBinding, .forceRun) {}
        world.sessions.cancelHeavy()
        gate.open()
        await first.value
        world.sessions.cancelHeavy()
        expectEqual(focusedInBody, 1)
        expectEqual(focusLog, []) // The focus didn't go to 2 and back
        expectEqual(fake.focused, 1)
    }

    @Test
    func focusCallbacksRunInTheOrderOfTheFocusChanges() async throws {
        setUpTree("h_tiles(*1)", workspace: "a")
        setUpTree("h_tiles(3)", workspace: "b")
        fake.focused = 1
        await heavyRefresh()
        logFocusOnFocusChanged(.workspace)
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
        expectEqual(focusLog, ["b", "c"])
    }

    /// The user focuses workspace b, whose focus callback suspends, then goes to `workspaces` with light sessions. Their
    /// focus changes run the callbacks after b's, once, for the latest focus: not for a workspace that the user has left,
    /// and not at all when the focus ends where it started
    @Test(arguments: [(["c"], ["b", "c"]), (["c", "d", "e"], ["b", "e"]), (["c", "b"], ["b"])] as [([String], [String])])
    func focusChangesDuringSuspendedFocusCallbacksRunThemAfterwardsForTheLatestFocus(
        workspaces: [String],
        expectedLog: [String],
    ) async throws {
        setUpTree("h_tiles(*1)", workspace: "a")
        setUpTree("h_tiles(3)", workspace: "b")
        fake.focused = 1
        await heavyRefresh()
        let gate = Gate()
        logFocusOnFocusChanged(.workspace, then: gate)

        fake.focused = 3
        let heavy = Task.startUnstructured { await heavyRefresh() }
        await gate.untilWaiting() // b's callback suspends
        for workspace in workspaces {
            _ = try await world.sessions.light(.hotkeyBinding, .forceRun) { await runCmd("workspace \(workspace)") }
        }
        world.sessions.cancelHeavy()
        expectEqual(focusLog, ["b"]) // The callbacks of the other focus changes wait for b's
        gate.open()
        await heavy.value
        expectEqual(focusLog, expectedLog)
    }

    /// Other sessions' focus changes while the callbacks suspend are queued for after them. The callbacks' own changes
    /// aren't: queued, they would run the callbacks again
    @Test
    func aFocusChangeThatTheFocusCallbacksMakeDoesntRunThemAgain() async throws {
        setUpTree("h_tiles(*1 2 3)")
        fake.focused = 1
        await heavyRefresh()
        logFocusOnFocusChanged(.window)
        let focusRight = parseCommand("focus --boundaries-action stop right").cmdOrDie
        world.config.onFocusChanged = .op(.seq, world.config.onFocusChanged, focusRight)

        _ = try await world.sessions.light(.hotkeyBinding, .forceRun) { await runCmd("focus right") }
        world.sessions.cancelHeavy()
        expectEqual(focusLog, ["2"]) // No recursion: the callback's own change to 3 doesn't run it again
        expectEqual(focus.windowOrNil?.windowId, 3)
    }

    @Test
    func theFocusCallbacksSeeATidyTree() async throws {
        world.config.enableNormalizationFlattenContainers = true
        setUpTree("h_tiles(*1 v_tiles(2 3))")
        fake.focused = 1
        await heavyRefresh()
        logFocusOnFocusChanged(.tree)

        _ = try await world.sessions.light(.hotkeyBinding, .forceRun) { // A body that isn't a command, e.g. a mouse drag
            testWindow(3).move(to: Workspace.get(byName: "b").rootTilingContainerCreatingIfNeeded())
            _ = testWindow(2).focusWindow()
        }
        world.sessions.cancelHeavy()
        expectEqual(focusLog, ["h_tiles(1 *2)"])
    }

    @Test
    func debugWindowsRecordsTheWindowThatALightSessionRegistered() async throws {
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
    func aHiddenAppsWindowDoesntTakeTheFocus() async throws { // RB-145
        fake.apps = [appA, appB]
        openWindow(1, appA)
        openWindow(2, appA)
        openWindow(3, appB)
        fake.focused = 2
        await heavyRefresh()
        fake.hiddenApps = [appB.pid] // cmd-h on B
        await heavyRefresh() // 3 moves to macos_hidden: that makes it the workspace's most recent window
        expectEqual(describeTree(), "h_tiles(1 *2) macos_hidden(3)")

        fake.resetCalls()
        _ = try await world.sessions.light(.hotkeyBinding, .forceRun) { await runCmd("move-node-to-workspace b") }
        world.sessions.cancelHeavy()
        expectEqual(focus.windowOrNil?.windowId, 1)
        _ = try await world.sessions.light(.hotkeyBinding, .forceRun) { await runCmd("move-node-to-workspace b") }
        world.sessions.cancelHeavy()
        expectEqual(focus.windowOrNil?.windowId, nil) // Only 3 is left: the workspace is focused as an empty one
        expectEqual(fake.calls(of: .focus), [.focus(1)]) // The native focus would unhide B
    }

    @Test
    func minimizingAWindowThatMacosMinimizedBeforeTheRefreshKeepsItMinimized() async {
        openWindow(1)
        openWindow(2)
        fake.focused = 1
        await heavyRefresh()
        fake.windows[1]?.isMinimized = true // cmd-m, and no heavy refresh has seen it yet

        fake.resetCalls()
        expectEqual(await runCmd("macos-native-minimize --window-id 1"), .ok)
        expectEqual(fake.calls(of: .setNative), []) // Before: it unminimized the window, then failed
        #expect(Window.get(byId: 1)?.parent === macosMinimizedWindowsContainer)
        expectEqual(describeTree(), "h_tiles(*2)")
    }

    @Test
    func focusFollowsMouseFocusesOnceAndKeepsTheScheduledHeavyRefresh() async throws {
        setUpTree("h_tiles(*1 2)")
        fake.focused = 1
        openWindow(3)

        world.sessions.scheduleHeavy(.ax("test"))
        try await world.sessions.focusFollowsMouse(testWindow(2), .forceRun)
        expectEqual(fake.calls(of: .focus), [.focus(2)])
        try await world.sessions.focusFollowsMouse(testWindow(2), .forceRun) // macOS focuses 2 already
        expectEqual(fake.calls(of: .focus), [.focus(2)])
        for _ in 0 ..< 100 where Window.get(byId: 3) == nil { await Task.yield() } // Let the heavy refresh run
        expectEqual(describeTree(), "h_tiles(1 *2 3)")
    }
}

private let appA = AppInfo(pid: 1, bundleId: "test.a", name: "A", execPath: nil, bundlePath: nil)
private let appB = AppInfo(pid: 2, bundleId: "test.b", name: "B", execPath: nil, bundlePath: nil)

/// What the on-focus-changed callback ``LogFocus`` saw, in order
private var focusLog: [String] = []
/// Awaited by ``LogFocus`` after each entry: the callback suspends there, as one that reads AX does
private var focusLogGate: Gate? = nil

/// on-focus-changed logs the focus that it sees into ``focusLog``, then waits for `gate`
private func logFocusOnFocusChanged(_ property: LogFocus.Property, then gate: Gate? = nil) {
    focusLog = []
    focusLogGate = gate
    world.config.onFocusChanged = .cmd(LogFocus(property: property))
}

/// Logs the focus that it sees: the focused workspace, the focused window, or the focused workspace's tree
private struct LogFocus: nonisolated Command {
    nonisolated enum Property { case workspace, window, tree }
    static let resetsClosedWindowsCache = false
    var source: SourceWords = ["log-focus"]
    let property: Property

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let target = try cx.target()
        let entry = switch property {
            case .workspace: target.workspace.name
            case .window: target.windowOrNil.map { "\($0.windowId)" } ?? "nil"
            case .tree: describeTree(target.workspace.name)
        }
        focusLog.append(entry)
        await focusLogGate?.wait()
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
