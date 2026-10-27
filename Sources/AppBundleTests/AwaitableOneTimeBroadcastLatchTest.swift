@testable import AppBundle
import Common
import os
import Testing

@Suite
struct AwaitableOneTimeBroadcastLatchTest {
    @Test
    func testAwaitAfterSignalReturnsImmediately() async throws {
        let latch = AwaitableOneTimeBroadcastLatch()
        await latch.signalToAll()
        try await latch.await()
    }

    @Test
    func testAwaitOnFreshLatchSuspendsUntilSignal() async throws {
        let latch = AwaitableOneTimeBroadcastLatch()
        let returnedCount = OSAllocatedUnfairLock(initialState: 0)
        let task = Task.startUnstructured {
            try await latch.await()
            returnedCount.withLock { $0 += 1 }
        }
        try await Task.sleep(for: .milliseconds(50))
        expectEqual(returnedCount.withLock { $0 }, 0)
        await latch.signalToAll()
        try await task.value
        expectEqual(returnedCount.withLock { $0 }, 1)
    }

    @Test
    func testSignalReleasesAllPendingAwaiters() async throws {
        let latch = AwaitableOneTimeBroadcastLatch()
        let count = 20
        let returnedCount = OSAllocatedUnfairLock(initialState: 0)
        let tasks = (0 ..< count).map { _ in
            Task.startUnstructured {
                try await latch.await()
                returnedCount.withLock { $0 += 1 }
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        expectEqual(returnedCount.withLock { $0 }, 0)
        await latch.signalToAll()
        for task in tasks { try await task.value }
        expectEqual(returnedCount.withLock { $0 }, count)
    }

    @Test
    func testSignalIsIdempotent() async throws {
        let latch = AwaitableOneTimeBroadcastLatch()
        await latch.signalToAll()
        await latch.signalToAll()
        await latch.signalToAll()
        try await latch.await()
        try await latch.await()
    }

    @Test
    func testSignalWithNoAwaiters() async throws {
        let latch = AwaitableOneTimeBroadcastLatch()
        await latch.signalToAll()
        try await latch.await()
    }

    @Test
    func testCancellingPendingAwaiterThrows() async throws {
        let latch = AwaitableOneTimeBroadcastLatch()
        let task = Task.startUnstructured { try await latch.await() }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test
    func testCancellingOneAwaiterDoesNotAffectOthers() async throws {
        let latch = AwaitableOneTimeBroadcastLatch()
        let cancelled = Task.startUnstructured { try await latch.await() }
        let survivors = (0 ..< 5).map { _ in Task.startUnstructured { try await latch.await() } }
        try await Task.sleep(for: .milliseconds(50))
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        await latch.signalToAll()
        for task in survivors { try await task.value }
    }

    @Test
    func testAwaitBailsWhenTaskIsAlreadyCancelled() async {
        let latch = AwaitableOneTimeBroadcastLatch()
        let task = Task.startUnstructured { () async throws in
            while !Task.isCancelled { await Task.yield() }
            try await latch.await()
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test
    func testSignalAfterCancellationStillReleasesRemainingAwaiters() async throws {
        let latch = AwaitableOneTimeBroadcastLatch()
        let cancelled = Task.startUnstructured { try await latch.await() }
        let lateJoiner = Task.startUnstructured { try await latch.await() }
        try await Task.sleep(for: .milliseconds(50))
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        await latch.signalToAll()
        try await lateJoiner.value
        // New await arriving after the signal still returns immediately.
        try await latch.await()
    }
}
