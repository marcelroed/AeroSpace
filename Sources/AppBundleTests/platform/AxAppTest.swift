@testable import AppBundle
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
        for i in 0 ..< 1000 {
            app.post { _ in log.append("\(i) \(Thread.current.name ?? "")") }
        }
        // An awaited call runs after the posts before it
        expectEqual(await app.run { _ in Thread.current.name }, "AxAppTest")
        expectEqual(log.items, (0 ..< 1000).map { "\($0) AxAppTest" })
        expectEqual(try await app.call { _, _ in Thread.current.name }, "AxAppTest")
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
