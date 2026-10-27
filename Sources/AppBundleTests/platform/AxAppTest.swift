@testable import AppBundle
import AppKit
import Common
import Foundation
import Synchronization
import Testing

// The actor and its executor without AX: the bodies are plain closures, and nothing subscribes. Creating an AxApp creates
// an app AXUIElement, which makes no AX call
@Suite
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
        // Like a layout: a write, then a read that must see it (hideInCorner), then a write again
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

    @Test
    func postAndWaitGivesUpOnAHungApp() { // RB-76
        let app = AxApp(pid: 0, threadName: "Hung")
        let gate = DispatchSemaphore(value: 0)
        app.post { _ in gate.wait() }
        #expect(!app.postAndWait(timeout: .milliseconds(50)) { _ in })
        gate.signal()
        #expect(app.postAndWait(timeout: .seconds(5)) { _ in })
    }

    @Test
    func aWindowWriteMakesTheEarlierWritesOfTheSameWindowStale() async {
        let app = AxApp(pid: 0, threadName: "AxAppTest")
        let gate = DispatchSemaphore(value: 0)
        let log = Log<String>()
        app.post { _ in gate.wait() }
        app.postWindowWrite(1) { _, isLatest in log.append("placement of 1: \(isLatest())") }
        app.postWindowWrite(2) { _, isLatest in log.append("placement of 2: \(isLatest())") }
        app.postWindowWrite(1) { _, isLatest in log.append("attribute of 1: \(isLatest())") }
        gate.signal()
        await app.run { _ in }
        expectEqual(log.items, ["placement of 1: false", "placement of 2: true", "attribute of 1: true"])
        app.postWindowWrite(1) { _, isLatest in log.append("placement of 1: \(isLatest())") }
        await app.run { _ in }
        expectEqual(log.items.last, "placement of 1: true")
    }

    @Test
    func anActivationForgetsTheFailedRegistrationsOfItsApp() { // RB-113
        let pid = NSRunningApplication.current.processIdentifier
        let platform = LivePlatform()
        platform.failedRegistrations[pid] = RegistrationBackoff(after: nil, now: .now)
        platform.forgetFailedRegistration(Notification(
            name: NSWorkspace.didActivateApplicationNotification,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current],
        ))
        expectEqual(platform.failedRegistrations[pid], nil)
    }

    @Test
    func failedRegistrationsBackOffFrom1To60Seconds() { // RB-113
        let now: ContinuousClock.Instant = .now
        var backoff: RegistrationBackoff? = nil
        var delays: [Duration] = []
        for _ in 0 ..< 8 {
            let next = RegistrationBackoff(after: backoff, now: now)
            delays.append(next.delay)
            backoff = next
        }
        expectEqual(delays, [1, 2, 4, 8, 16, 32, 60, 60].map { Duration.seconds($0) })
        expectEqual(backoff?.retryAt, now + .seconds(60))
    }
}

nonisolated private let timerCallbackEnteredTheActor: Atomic<Bool> = Atomic(false)

nonisolated private func enterTheActor(_: CFRunLoopTimer?, _ info: UnsafeMutableRawPointer?) {
    guard let info = unsafe info else { return }
    // Traps unless the executor tells the runtime that this thread is the actor's (P1)
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
