@testable import AppBundle
import Common
import Testing

/// The deadlines of the window listings (R2b L3), on a listing that the test holds with ``Gate``s
@Suite(.aeroSpaceGlobalState)
struct ListingDeadlinesTest {
    @Test
    func aCancelledListingDoesntClearTheLateMarkOfANewerOne() async throws { // R2c L1
        let deadlines = ListingDeadlines(minDeadline: .milliseconds(20), maxDeadline: .seconds(1))
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

    @Test
    func aSlowAnswerDoesntStretchTheDeadlinePastTheCap() async throws { // R2c M2
        let deadlines = ListingDeadlines(minDeadline: .milliseconds(1), maxDeadline: .milliseconds(20))
        let answer = try await deadlines.list(7, hasDeadline: false) { () async throws(CancellationError) -> [Int]? in
            try? await Task.sleep(for: .milliseconds(30)) // E.g. AX timeouts inside the listing of an app that turned busy
            return [1]
        }
        expectEqual(answer, [1])
        expectEqual(deadlines.deadline(7), .milliseconds(20))

        let noAnswer = try await deadlines.list(7, hasDeadline: true) { () async throws(CancellationError) -> [Int]? in nil }
        expectEqual(noAnswer, nil) // The AX timeout of a hung app
        expectEqual(deadlines.deadline(7), .milliseconds(1))
    }

    @Test
    func aLateAnswerGivesOnlyTheNextListingALongerDeadline() async throws { // R2c M2
        let deadlines = ListingDeadlines(minDeadline: .milliseconds(1), maxDeadline: .milliseconds(20))
        let slowness = Gate()
        fake.resetCalls()
        let late = try await deadlines.list(7, hasDeadline: true) { () async throws(CancellationError) -> [Int]? in
            await slowness.wait()
            return [1]
        }
        expectEqual(late, nil)
        try? await Task.sleep(for: .milliseconds(30))
        slowness.open() // The answer took more than 30 ms: twice that is past the cap
        for _ in 0 ..< 100 where fake.calls(of: .listWindows).isEmpty { await Task.yield() }
        world.sessions.cancelHeavy() // The heavy refresh that lists the app again
        #expect(deadlines.deadline(7) >= .milliseconds(60)) // The app gets its windows registered

        let answer = try await deadlines.list(7, hasDeadline: true) { () async throws(CancellationError) -> [Int]? in [1] }
        expectEqual(answer, [1])
        #expect(deadlines.deadline(7) <= .milliseconds(20))
    }
}
