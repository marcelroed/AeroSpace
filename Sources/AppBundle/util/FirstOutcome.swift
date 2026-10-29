import Synchronization

/// The outcome of a race, e.g. an answer against a deadline and the caller's cancellation. The first ``resolve(_:)`` wins,
/// from any thread, before or after the caller suspends in ``wait(onCancel:)``
nonisolated final class FirstOutcome<T: Sendable>: Sendable {
    private enum State {
        case pending(waiter: CheckedContinuation<T, Never>?)
        case resolved(T)
    }

    private let state: Mutex<State> = Mutex(.pending(waiter: nil))

    var isResolved: Bool {
        state.withLock { state in
            if case .resolved = state { true } else { false }
        }
    }

    /// Waits for the outcome. Cancelling the caller resolves it with `onCancel`. Call it once
    func wait(onCancel: T) async -> T {
        await withTaskCancellationHandler {
            await withCheckedContinuation { waiter in
                let early: T? = state.withLock { state in
                    switch state {
                        case .pending:
                            state = .pending(waiter: waiter)
                            return nil
                        case .resolved(let outcome):
                            return outcome
                    }
                }
                if let early { waiter.resume(returning: early) }
            }
        } onCancel: {
            resolve(onCancel)
        }
    }

    /// nil if this call resolved it, else the outcome that did
    @discardableResult
    func resolve(_ outcome: T) -> T? {
        let (earlier, waiter): (T?, CheckedContinuation<T, Never>?) = state.withLock { state in
            switch state {
                case .pending(let waiter):
                    state = .resolved(outcome)
                    return (nil, waiter)
                case .resolved(let earlier):
                    return (earlier, nil)
            }
        }
        waiter?.resume(returning: outcome)
        return earlier
    }
}
