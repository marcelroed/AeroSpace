import Common
import Foundation

/// The deadline of each app's window listing in a heavy refresh: a hung app doesn't hold the refresh's reads of
/// the other apps. An app that misses its deadline doesn't answer for this refresh, and its listing goes on; until that
/// listing returns, the refreshes don't ask the app again.
///
/// The deadline is twice the app's last answer time, between `minDeadline` and `maxDeadline`. An app that doesn't answer
/// (an AX timeout) is back at `minDeadline`. The cap keeps one slow answer (e.g. the listing of an app that turned busy
/// during it, with AX timeouts inside) from holding every refresh while the app stays busy. If a late listing
/// answers, a heavy refresh lists the app again, and the deadline is twice the late answer's time, past the cap, until a
/// listing answers or misses it (a cancelled refresh keeps it): a slow app gets its windows registered. The late
/// answer itself is dropped: it may be older than a window that a light session registered since, and the GC would drop
/// that one
final class ListingDeadlines {
    /// The deadline of an app that answered fast, never, or not at all the last time
    private let minDeadline: Duration
    /// The deadline of an app that answered slowly, well below the AX timeout
    private let maxDeadline: Duration
    /// How long each app's last answer by its deadline took
    private var answerTimes: [pid_t: Duration] = [:]
    /// The apps whose listing missed its deadline and still runs
    private var lateApps: Set<pid_t> = []
    /// How long each app's late answer took, until a listing with a deadline answers in time or misses it. A cancelled
    /// refresh doesn't use it up: its listing can be cancelled by another app's late answer
    private var lateAnswerTimes: [pid_t: Duration] = [:]
    /// Waits until a deadline passes: `Task.sleep`, or a test's gate
    private let sleep: (Duration) async -> ()

    init(
        minDeadline: Duration,
        maxDeadline: Duration,
        sleep: @escaping (Duration) async -> () = { try? await Task.sleep(for: $0) },
    ) {
        self.minDeadline = minDeadline
        self.maxDeadline = maxDeadline
        self.sleep = sleep
    }

    /// The deadline of the app's next listing
    func deadline(_ pid: pid_t) -> Duration {
        let usual = min(maxDeadline, max(minDeadline, (answerTimes[pid] ?? .zero) * 2))
        return max(usual, (lateAnswerTimes[pid] ?? .zero) * 2)
    }

    /// The app's listing (`list`), nil if the app didn't answer. Without a deadline (the startup's refresh, which
    /// registers the windows the startup's way) it's awaited. Cancelling the refresh before the deadline cancels it
    func list<T: Sendable>(
        _ pid: pid_t,
        hasDeadline: Bool,
        _ list: @escaping () async throws(CancellationError) -> T?,
    ) async throws(CancellationError) -> T? {
        try checkCancellation()
        if lateApps.contains(pid) { return nil }
        let start = ContinuousClock.now
        if !hasDeadline {
            let answer = try await list()
            record(pid, answer, since: start)
            return answer
        }
        let deadline = deadline(pid)
        let race: FirstOutcome<ListingOutcome<T>> = FirstOutcome()
        let listing = Task.startUnstructured { [self] in
            let answer: T?? = try? await list() // nil: cancelled
            switch race.resolve(answer.map { .answer($0) } ?? .cancelled) {
                case nil: // By the deadline
                    if let answer {
                        record(pid, answer, since: start)
                        lateAnswerTimes[pid] = nil
                    }
                case .deadline:
                    // Late: the refresh went on without the app. Only a late listing clears the mark: the listing of a
                    // refresh that was cancelled before the deadline didn't set it, a newer listing did
                    lateApps.remove(pid)
                    switch answer {
                        case .some(.some):
                            lateAnswerTimes[pid] = start.duration(to: .now)
                            world.sessions.scheduleHeavy(.lateListing)
                        case .some(.none): answerTimes[pid] = nil
                        case .none: break
                    }
                case .answer, .cancelled: break // The refresh was cancelled first
            }
        }
        let timer = Task.startUnstructured { [self] in
            await sleep(deadline)
            if race.resolve(.deadline) == nil {
                lateApps.insert(pid)
                lateAnswerTimes[pid] = nil // Here, not after the refresh resumes: the late answer may come first
            }
        }
        let outcome = await race.wait(onCancel: .cancelled)
        timer.cancel()
        switch outcome {
            case .answer(let answer): return answer
            case .deadline: return nil
            case .cancelled:
                listing.cancel()
                throw CancellationError()
        }
    }

    private func record<T>(_ pid: pid_t, _ answer: T?, since start: ContinuousClock.Instant) {
        answerTimes[pid] = answer == nil ? nil : start.duration(to: .now)
    }
}

nonisolated private enum ListingOutcome<T: Sendable>: Sendable {
    case answer(T?), deadline, cancelled
}
