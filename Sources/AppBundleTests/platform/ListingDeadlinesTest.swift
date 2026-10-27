@testable import AppBundle
import Common
import Testing

/// The deadlines of the window listings (R2b L3), on a listing that the test holds with ``Gate``s
@Suite(.aeroSpaceGlobalState)
struct ListingDeadlinesTest {
    @Test
    func aCancelledListingDoesntClearTheLateMarkOfANewerOne() async throws { // R2c L1
        let deadline = Gate()
        let deadlines = ListingDeadlines(minDeadline: .milliseconds(1), maxDeadline: .seconds(1)) { _ in await deadline.wait() }
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
        deadline.open()
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

    @Test
    func aCancelledListingKeepsTheLongerDeadline() async throws { // R2d M1
        let longDeadline = Gate()
        let deadlines = ListingDeadlines(minDeadline: .nanoseconds(1), maxDeadline: .nanoseconds(1)) { deadline in
            if deadline > .nanoseconds(1) { await longDeadline.wait() } // A deadline past the cap passes at the end
        }
        let slowness = Gate()
        fake.resetCalls()
        let late = try await deadlines.list(7, hasDeadline: true) { () async throws(CancellationError) -> [Int]? in
            await slowness.wait()
            return [1]
        }
        expectEqual(late, nil)
        slowness.open() // The late answer gives the next listing a longer deadline
        for _ in 0 ..< 100 where fake.calls(of: .listWindows).isEmpty { await Task.yield() }
        world.sessions.cancelHeavy()
        let longer = deadlines.deadline(7)
        #expect(longer > .nanoseconds(1))

        let hold = Gate()
        let cancelled = Task.startUnstructured {
            _ = try? await deadlines.list(7, hasDeadline: true) { () async throws(CancellationError) -> [Int]? in
                await hold.wait()
                return [1]
            }
        }
        await hold.untilWaiting()
        cancelled.cancel() // E.g. another app's late answer replaced the refresh
        await cancelled.value
        hold.open()
        for _ in 0 ..< 10 { await Task.yield() }
        expectEqual(deadlines.deadline(7), longer) // Still there for the next refresh

        let answer = try await deadlines.list(7, hasDeadline: true) { () async throws(CancellationError) -> [Int]? in [1] }
        expectEqual(answer, [1])
        expectEqual(deadlines.deadline(7), .nanoseconds(1)) // Used up by the listing that answered
        longDeadline.open()
    }

    @Test
    func aListingThatMissesTheLongerDeadlineUsesItUp() async throws { // R2d M1
        let longDeadline = Gate()
        let deadlines = ListingDeadlines(minDeadline: .nanoseconds(1), maxDeadline: .nanoseconds(1)) { deadline in
            if deadline > .nanoseconds(1) { await longDeadline.wait() }
        }
        let (first, second) = (Gate(), Gate())
        var calls = 0
        let list = { () async throws(CancellationError) -> [Int]? in
            calls += 1
            await (calls == 1 ? first : second).wait()
            return [1]
        }
        fake.resetCalls()
        let late = try await deadlines.list(7, hasDeadline: true, list)
        expectEqual(late, nil)
        first.open() // The late answer gives the next listing a longer deadline
        for _ in 0 ..< 100 where fake.calls(of: .listWindows).isEmpty { await Task.yield() }
        world.sessions.cancelHeavy()
        #expect(deadlines.deadline(7) > .nanoseconds(1))

        var missed: [Int]?? = .none
        let listing = Task.startUnstructured { missed = try? await deadlines.list(7, hasDeadline: true, list) }
        await second.untilWaiting()
        longDeadline.open() // The app is slower still: it misses the longer deadline too
        await listing.value
        expectEqual(missed, .some(nil))
        expectEqual(deadlines.deadline(7), .nanoseconds(1))
        second.open()
        for _ in 0 ..< 10 { await Task.yield() }
        world.sessions.cancelHeavy()
    }
}
