@testable import AppBundle
import AppKit
import Common
import Foundation
import Synchronization
import Testing

// The actor and its executor without AX: the bodies are plain closures, and nothing subscribes. Creating an AxApp creates
// an app AXUIElement, which makes no AX call. Serialized: a test sets `isTerminating`, which every AxApp reads
@Suite(.serialized)
struct AxAppTest {
    @Test
    func postsAndAwaitedCallsRunInFifoOrderOnTheAppThread() async throws {
        let app = AxApp(pid: 0, threadName: "AxAppTest")
        let log = Log<String>()
        // A second poster on another thread meanwhile. Its posts keep their own order
        DispatchQueue.global().async {
            for i in 0 ..< 5000 {
                app.post { _ in log.append("other \(i) \(Thread.current.name ?? "")") }
            }
        }
        // Like a command: a write, then a read that must see it, then a write again
        var expected: [String] = []
        for i in 0 ..< 300 {
            app.post { _ in log.append("post \(i) \(Thread.current.name ?? "")") }
            if i.isMultiple(of: 2) {
                await app.run { _ in log.append("run \(i) \(Thread.current.name ?? "")") }
                expected += ["post \(i) AxAppTest", "run \(i) AxAppTest"]
            } else {
                try await app.call { _, _ in log.append("call \(i) \(Thread.current.name ?? "")") }
                expected += ["post \(i) AxAppTest", "call \(i) AxAppTest"]
            }
        }
        try await waitUntil { log.items.count == expected.count + 5000 }
        expectEqual(log.items.filter { !$0.hasPrefix("other") }, expected)
        expectEqual(log.items.filter { $0.hasPrefix("other") }, (0 ..< 5000).map { "other \($0) AxAppTest" })
    }

    @Test
    func aRunLoopCallbackOnTheAppThreadEntersTheActor() async throws {
        let app = AxApp(pid: 0, threadName: "AxAppTest")
        await app.run { app in
            // Like the AXObserver callback: a C callback on the app's run loop, with the unretained app as its context
            var context = unsafe CFRunLoopTimerContext(
                version: 0,
                info: Unmanaged.passUnretained(app).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil,
            )
            let timer = unsafe CFRunLoopTimerCreate(nil, CFAbsoluteTimeGetCurrent() + 0.01, 0, 0, 0, enterTheActor, &context)
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)
        }
        try await waitUntil { timerCallbackEnteredTheActor.load(ordering: .sequentiallyConsistent) }
    }

    @Test
    func theLastReleaseOnMainRunsTheDeinitOnTheAppThread() async throws {
        // Its own pid: the test watches the retain count of the app's element
        var app: AxApp? = AxApp(pid: 99999, threadName: "AxAppTest")
        let element: ElementRef? = await app?.run { ElementRef(element: $0.element) }
        let thread: ThreadRef? = await app?.run { _ in ThreadRef(thread: Thread.current) }
        // Block the app thread with a run loop timer: unlike a post, it doesn't retain the actor
        await app?.run { _ in
            let timer = unsafe CFRunLoopTimerCreate(nil, CFAbsoluteTimeGetCurrent(), 0, 0, 0, blockTheAppThread, nil)
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)
        }
        try await waitUntil { isAppThreadBlocked.load(ordering: .sequentiallyConsistent) }
        let retainCount = element.map { CFGetRetainCount($0.element) }
        app = nil // The last reference, dropped on main
        // The deinit didn't run here: the actor's storage (which holds the element) is still alive
        expectEqual(element.map { CFGetRetainCount($0.element) }, retainCount)
        appThreadGate.signal()
        try await waitUntil { thread?.thread.isFinished == true }
        // It ran on the app thread after the timer, then stopped the thread
        expectEqual(element.map { CFGetRetainCount($0.element) }, retainCount.map { $0 - 1 })
    }

    @Test
    func releasingTheActorStopsItsThreadAfterThePendingPosts() async throws {
        var app: AxApp? = AxApp(pid: 0, threadName: "AxAppTest")
        let thread: ThreadRef? = await app?.run { _ in ThreadRef(thread: Thread.current) }
        let gate = DispatchSemaphore(value: 0)
        let log = Log<Int>()
        app?.post { _ in gate.wait() }
        for i in 0 ..< 100 {
            app?.post { _ in log.append(i) }
        }
        app = nil // The posts retain the actor: its isolated deinit runs after them, and stops the thread
        gate.signal()
        try await waitUntil { thread?.thread.isFinished == true }
        expectEqual(log.items, Array(0 ..< 100))
    }

    @Test
    func aHungAppDoesntBlockAnotherApp() async {
        let hung = AxApp(pid: 0, threadName: "Hung")
        let healthy = AxApp(pid: 0, threadName: "Healthy")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        hung.post { _ in gate.wait() }
        expectEqual(await healthy.run { _ in 42 }, 42)
        #expect(healthy.postAndWait(timeout: .seconds(5)) { _ in })
    }

    @Test
    func anAbandonedCallReturnsAtOnceAndSkipsItsBody() async {
        let app = AxApp(pid: 0, threadName: "Hung")
        let gate = DispatchSemaphore(value: 0)
        let log = Log<String>()
        app.post { _ in gate.wait() }
        let outcome: String = await withTaskGroup(of: String.self) { group in
            group.addTask {
                do {
                    return "returned \(try await app.call { _, _ in log.append("body ran") })"
                } catch {
                    return "cancelled"
                }
            }
            try? await Task.sleep(for: .milliseconds(50)) // Most likely suspended in the call by now
            group.cancelAll()
            return await group.next() ?? ""
        }
        expectEqual(outcome, "cancelled") // While the app is still hung
        gate.signal()
        await app.run { _ in } // After the abandoned call's job
        expectEqual(log.items, [])
    }

    /// Once termination starts, a read that runs on the app's thread returns without running its body: the restore job
    /// waits behind it
    @Test
    func terminationSkipsTheBodiesOfTheReads() async {
        let app = AxApp(pid: 0, threadName: "AxAppTest")
        let log = Log<String>()
        isTerminating.store(true, ordering: .sequentiallyConsistent)
        defer { isTerminating.store(false, ordering: .sequentiallyConsistent) }

        let run: Int? = await app.run { _ in
            log.append("run")
            return 1
        }
        let call: Int? = try? await app.call { _, _ in
            log.append("call")
            return 1
        }

        expectEqual(run, nil)
        expectEqual(call, nil)
        expectEqual(log.items, [])
    }

    @Test
    func postAndWaitGivesUpOnAHungApp() { // RB-76
        let app = AxApp(pid: 0, threadName: "Hung")
        let gate = DispatchSemaphore(value: 0)
        app.post { _ in gate.wait() }
        #expect(!app.postAndWait(timeout: .milliseconds(50)) { _ in })
        gate.signal()
        #expect(app.postAndWait(timeout: .seconds(5)) { _ in })
    }

    /// Each layout parks every hidden window again, and in the steady state these parks move nothing
    @Test
    func aParksJobThatMovesNoWindowDoesntWaitForTheShownJobs() async {
        let hung = AxApp(pid: 0, threadName: "Hung")
        let parker = AxApp(pid: 0, threadName: "Parker")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        hung.post { _ in gate.wait() }
        let shownJobs = ShownJobs(deadline: .now() + .seconds(10))
        hung.postPlacements([], .shown(shownJobs, focus: nil), trustsLastSeen: false)
        let target = ParkTarget(corner: .bottomRightCorner, monitor: testMonitor, monitors: NonEmptyArray(testMonitor), isFloating: false, isZoom: false)
        parker.postPlacements([.park(1, target)], .parks(waitingFor: shownJobs), trustsLastSeen: false) // The parker has no window 1

        let start: DispatchTime = .now()
        await parker.run { _ in } // After the parks job
        #expect(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds < 5_000_000_000)
    }

    /// pid-0 apps have no windows to write, so the parker calls what its first write calls (`AnimationsOff`)
    @Test
    func aParksJobsFirstWriteWaitsForEveryShownJobUntilTheDeadline() async throws {
        let slow = AxApp(pid: 0, threadName: "Slow")
        let hung = AxApp(pid: 0, threadName: "Hung")
        let parker = AxApp(pid: 0, threadName: "Parker")
        let slowGate = DispatchSemaphore(value: 0)
        let hungGate = DispatchSemaphore(value: 0)
        defer { hungGate.signal() }
        let log = Log<String>()

        slow.post { _ in
            slowGate.wait()
            log.append("the slow app wrote")
        }
        let shownJobs = ShownJobs(deadline: .now() + .seconds(10))
        slow.postPlacements([], .shown(shownJobs, focus: nil), trustsLastSeen: false)
        parker.post { _ in
            shownJobs.wait()
            log.append("the parker writes")
        }
        try await Task.sleep(for: .milliseconds(50))
        expectEqual(log.items, [])
        slowGate.signal()
        try await waitUntil { log.items.count == 2 }
        expectEqual(log.items, ["the slow app wrote", "the parker writes"])

        hung.post { _ in hungGate.wait() }
        let start: DispatchTime = .now()
        let shownJobsWithAHungApp = ShownJobs(deadline: start + .milliseconds(100))
        hung.postPlacements([], .shown(shownJobsWithAHungApp, focus: nil), trustsLastSeen: false)
        await parker.run { _ in shownJobsWithAHungApp.wait() }
        let waited = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        #expect(waited >= 100_000_000 && waited < 5_000_000_000, "waited \(waited) ns")
    }

    /// The native focus runs on its app's thread inside the app's shown job: after the app's earlier jobs and the job's
    /// writes (pid-0 apps have none), before the parks may go. A slow focus shows it: the parker would go meanwhile
    @Test
    func aShownJobGivesTheNativeFocusBeforeTheParksMayGo() async throws {
        let focused = AxApp(pid: 0, threadName: "Focused")
        let parker = AxApp(pid: 0, threadName: "Parker")
        let log = Log<String>()
        let shownJobs = ShownJobs(deadline: .now() + .seconds(10))

        focused.post { _ in log.append("an earlier job") }
        focused.postPlacements([], .shown(shownJobs, focus: { @Sendable _ in
            Thread.sleep(forTimeInterval: 0.05)
            log.append("the focus on \(Thread.current.name ?? "")")
        }), trustsLastSeen: false)
        parker.post { _ in
            shownJobs.wait()
            log.append("the parks go")
        }

        try await waitUntil { log.items.count == 3 }
        expectEqual(log.items, ["an earlier job", "the focus on Focused", "the parks go"])
    }

    @Test
    func theWaitForAnUnparkedTileEndsOnceItLeftItsCornerClosedOrWasWrittenAgain() {
        let cornerX: CGFloat = 1919
        // The window server's x of the window, one per lookup, the last one repeated
        let rows: [(name: String, shown: [CGFloat?], isCurrent: Bool, lookups: Int)] = [
            ("left its corner", [cornerX, cornerX, 0], true, 3),
            ("put a bit off its frame by the app", [cornerX, 2], true, 2),
            ("closed", [cornerX, nil], true, 2),
            ("written again, or termination started", [cornerX], false, 0),
        ]
        for row in rows {
            var lookups = 0
            let start: DispatchTime = .now()
            let unparked = UnparkedTile(windowId: 1, cornerX: cornerX, isCurrent: { row.isCurrent })
            waitUntilOnScreen([unparked], until: .now() + .seconds(10)) { _ in
                defer { lookups += 1 }
                return row.shown[min(lookups, row.shown.count - 1)]
            }
            expectEqual(lookups, row.lookups, "\(row.name)")
            #expect(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds < 5_000_000_000, "\(row.name)")
        }

        let start: DispatchTime = .now()
        let neverMoves = UnparkedTile(windowId: 1, cornerX: cornerX, isCurrent: { true })
        waitUntilOnScreen([neverMoves], until: start + .milliseconds(50)) { _ in cornerX }
        #expect(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds >= 50_000_000, "gives up at the deadline")
    }

    @Test
    func aWindowWriteMakesTheEarlierWritesOfTheSameWindowStale() {
        var generations = WindowGenerations()
        let placementOf1 = generations.bump(1)
        let placementOf2 = generations.bump(2)
        let attributeOf1 = generations.bump(1)
        expectEqual(
            [generations.isLatest(1, placementOf1), generations.isLatest(2, placementOf2), generations.isLatest(1, attributeOf1)],
            [false, true, true],
        )
        generations.finish(1, placementOf1) // A stale write's end keeps the newer write
        #expect(generations.isLatest(1, attributeOf1))
        generations.finish(1, attributeOf1) // The last write's end forgets the window
        let newer = generations.bump(1)
        expectEqual([generations.isLatest(1, attributeOf1), generations.isLatest(1, newer)], [false, true])
    }

    @Test
    func failedRegistrationsBackOffFrom1To60Seconds() { // RB-113
        let backoffs = RegistrationBackoffs(observing: NotificationCenter())
        let failedAt: ContinuousClock.Instant = .now
        let delays: [Int] = [1, 2, 4, 8, 16, 32, 60, 60]
        for (index, delay) in delays.enumerated() {
            backoffs.failed(1, now: failedAt)
            let retryAt = failedAt + .seconds(delay)
            #expect(backoffs.isBackingOff(1, now: retryAt - .milliseconds(1)), "failure \(index + 1)")
            #expect(!backoffs.isBackingOff(1, now: retryAt), "failure \(index + 1)")
        }
        backoffs.forget(1)
        backoffs.failed(1, now: failedAt)
        #expect(!backoffs.isBackingOff(1, now: failedAt + .seconds(1)), "a forgotten app starts over at 1 s")
    }

    @Test
    func launchingActivatingOrTerminatingAnAppForgetsItsFailedRegistrations() { // RB-113
        let center = NotificationCenter()
        let backoffs = RegistrationBackoffs(observing: center)
        let app = NSRunningApplication.current
        let otherPid = app.processIdentifier + 1
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        let failedAt: ContinuousClock.Instant = .now
        for name in names {
            backoffs.failed(app.processIdentifier, now: failedAt)
            backoffs.failed(otherPid, now: failedAt)
            center.post(name: name, object: nil, userInfo: [NSWorkspace.applicationUserInfoKey: app])
            #expect(!backoffs.isBackingOff(app.processIdentifier, now: failedAt), "\(name.rawValue)")
            #expect(backoffs.isBackingOff(otherPid, now: failedAt), "\(name.rawValue): another app's")
        }
    }
}

nonisolated private let timerCallbackEnteredTheActor: Atomic<Bool> = Atomic(false)

nonisolated private func enterTheActor(_: CFRunLoopTimer?, _ info: UnsafeMutableRawPointer?) {
    guard let info = unsafe info else { return }
    // Traps unless the executor tells the runtime that this thread is the actor's (isIsolatingCurrentContext)
    let windowIds = unsafe Unmanaged<AxApp>.fromOpaque(info).takeUnretainedValue().assumeIsolated { $0.windowIds }
    timerCallbackEnteredTheActor.store(windowIds.isEmpty, ordering: .sequentiallyConsistent)
}

nonisolated private let isAppThreadBlocked: Atomic<Bool> = Atomic(false)
nonisolated private let appThreadGate: DispatchSemaphore = DispatchSemaphore(value: 0)

nonisolated private func blockTheAppThread(_: CFRunLoopTimer?, _: UnsafeMutableRawPointer?) {
    isAppThreadBlocked.store(true, ordering: .sequentiallyConsistent)
    appThreadGate.wait()
}

/// `AXUIElement` isn't Sendable. The test only reads its retain count, which is thread-safe
nonisolated private struct ElementRef: @unchecked Sendable {
    let element: AXUIElement
}

/// `Thread` isn't Sendable, but `isFinished` is safe to read from any thread
nonisolated private struct ThreadRef: @unchecked Sendable {
    let thread: Thread
}

nonisolated private final class Log<T: Sendable>: Sendable {
    private let _items: Mutex<[T]> = Mutex([])
    func append(_ item: T) { _items.withLock { $0.append(item) } }
    var items: [T] { _items.withLock { $0 } }
}

private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0 ..< 500 where !condition() {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition())
}
