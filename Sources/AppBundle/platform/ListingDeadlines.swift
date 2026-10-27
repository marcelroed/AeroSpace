import Common
import Foundation
import Synchronization

/// The deadline of each app's window listing in a heavy refresh (R2b L3): a hung app doesn't hold the refresh's reads of
/// the other apps. An app that misses its deadline doesn't answer for this refresh, and its listing goes on; until that
/// listing returns, the refreshes don't ask the app again. If it then answers, a heavy refresh lists the app again with a
/// deadline of twice the time that the answer took, so that a slow app gets its windows registered. The late answer
/// itself is dropped: it may be older than a window that a light session registered since, and the GC would drop that one
final class ListingDeadlines {
    /// The deadline of an app that answered fast, or never
    private let minDeadline: Duration
    /// How long each app's last answer took
    private var answerTimes: [pid_t: Duration] = [:]
    /// The apps whose listing missed its deadline and still runs
    private var lateApps: Set<pid_t> = []

    init(minDeadline: Duration) { self.minDeadline = minDeadline }

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
            if answer != nil { answerTimes[pid] = start.duration(to: .now) }
            return answer
        }
        let deadline = max(minDeadline, (answerTimes[pid] ?? .zero) * 2)
        let race = ListingRace<T>()
        var listing: Task<(), Never>? = nil
        var timer: Task<(), Never>? = nil
        let outcome = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                race.suspend(continuation)
                listing = Task.startUnstructured { [self] in
                    let answer: T?? = try? await list() // nil: cancelled
                    if case .some(.some) = answer { answerTimes[pid] = start.duration(to: .now) }
                    if race.resolve(answer.map { .answer($0) } ?? .cancelled) { return }
                    // Late: the refresh went on without the app
                    if lateApps.remove(pid) != nil, case .some(.some) = answer {
                        world.sessions.scheduleHeavy(.lateListing)
                    }
                }
                timer = Task.startUnstructured { [self] in
                    try? await Task.sleep(for: deadline)
                    if race.resolve(.deadline) { lateApps.insert(pid) }
                }
            }
        } onCancel: {
            race.resolve(.cancelled)
        }
        timer?.cancel()
        switch outcome {
            case .answer(let answer): return answer
            case .deadline: return nil
            case .cancelled:
                listing?.cancel()
                throw CancellationError()
        }
    }
}

nonisolated private enum ListingOutcome<T: Sendable>: Sendable {
    case answer(T?), deadline, cancelled
}

/// Resolved once: by the listing, by the deadline, or by the refresh's cancellation (on any thread)
nonisolated private final class ListingRace<T: Sendable>: Sendable {
    typealias Continuation = CheckedContinuation<ListingOutcome<T>, Never>
    private let state: Mutex<(continuation: Continuation?, outcome: ListingOutcome<T>?)> = Mutex((nil, nil))

    func suspend(_ continuation: Continuation) {
        let early: ListingOutcome<T>? = state.withLock { state in
            if state.outcome == nil { state.continuation = continuation }
            return state.outcome
        }
        if let early { continuation.resume(returning: early) }
    }

    /// false if the race is over already
    @discardableResult
    func resolve(_ outcome: ListingOutcome<T>) -> Bool {
        let (isFirst, continuation): (Bool, Continuation?) = state.withLock { state in
            if state.outcome != nil { return (false, nil) }
            state.outcome = outcome
            defer { state.continuation = nil }
            return (true, state.continuation)
        }
        continuation?.resume(returning: outcome)
        return isFirst
    }
}
