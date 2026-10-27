@testable import AppBundle
import Common
import Testing

/// The deadlines of the window listings (R2b L3), on a listing that the test holds with ``Gate``s
@Suite(.aeroSpaceGlobalState)
struct ListingDeadlinesTest {
    @Test
    func aCancelledListingDoesntClearTheLateMarkOfANewerOne() async throws { // R2c L1
        let deadlines = ListingDeadlines(minDeadline: .milliseconds(20))
        let (first, second) = (Gate(), Gate())
        var calls = 0
        let list = { () async throws(CancellationError) -> [Int]? in
            calls += 1
            await (calls == 1 ? first : second).wait() // As a slow registration does
            try checkCancellation()
            return [1]
        }
        fake.resetCalls()

        let cancelled = Task.startUnstructured { _ = try? await deadlines.list(7, hasDeadline: true, list) }
        await first.untilWaiting()
        cancelled.cancel() // The refresh is cancelled before the deadline. Its listing goes on
        await cancelled.value
        let late = try await deadlines.list(7, hasDeadline: true, list) // A newer refresh's listing misses the deadline
        expectEqual(late, nil)
        first.open() // The cancelled listing returns
        for _ in 0 ..< 10 { await Task.yield() }
        let whileLate = try await deadlines.list(7, hasDeadline: true, list)
        expectEqual(whileLate, nil)
        expectEqual(calls, 2) // The app isn't asked again while its late listing runs

        second.open() // The late listing answers: a heavy refresh lists the apps again
        for _ in 0 ..< 100 where fake.calls(of: .listWindows).isEmpty { await Task.yield() }
        expectEqual(fake.calls(of: .listWindows), [.listWindows])
        world.sessions.cancelHeavy()
    }
}
