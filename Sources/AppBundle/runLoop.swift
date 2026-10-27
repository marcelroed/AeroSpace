import Common
import Foundation
import os

extension Thread {
    @discardableResult
    func runInLoopAsync(
        job: RunLoopJob,
        autoCheckCancelled: Bool = true,
        _ body: @Sendable @escaping (RunLoopJob) -> (),
    ) -> RunLoopJob {
        let action = RunLoopAction(job: job, autoCheckCancelled: autoCheckCancelled, body)
        // Alternative: CFRunLoopPerformBlock + CFRunLoopWakeUp
        action.perform(#selector(action.action), on: self, with: nil, waitUntilDone: false)
        return job
    }

    func runInLoop<T>(
        _ cm: CancellationMode,
        _ body: @Sendable @escaping (RunLoopJob) throws -> T,
    ) async throws -> T { // todo try to convert to typed throws
        try checkCancellation(cm)
        let job = RunLoopJob(cm)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                // It's unsafe to implicitly cancel because cont.resume should be invoked exactly once
                self.runInLoopAsync(job: job, autoCheckCancelled: false) { job in
                    do {
                        try job.checkCancellation()
                        cont.resume(returning: try body(job))
                    } catch {
                        if cm == .nonCancellable { die() }
                        cont.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            job.cancel()
        }
    }
}

private final class RunLoopAction: NSObject, Sendable {
    private let _action: @Sendable (RunLoopJob) -> ()
    let job: RunLoopJob
    private let autoCheckCancelled: Bool
    private let _refreshSessionEvent: RefreshSessionEvent?
    init(job: RunLoopJob, autoCheckCancelled: Bool, _ action: @escaping @Sendable (RunLoopJob) -> ()) {
        self.job = job
        self.autoCheckCancelled = autoCheckCancelled
        _action = action
        _refreshSessionEvent = refreshSessionEvent
    }
    @objc func action() {
        if autoCheckCancelled && job.isCancelled { return }
        $refreshSessionEvent.withValue(_refreshSessionEvent) {
            _action(job)
        }
    }
}

final class RunLoopJob: Sendable, AeroAny {
    // Alternative: In macOS 15, it's possible to use `Atomic<Bool>` from `Synchronization` module
    private let _isCancelled = OSAllocatedUnfairLock(initialState: false)
    var isCancelled: Bool { _isCancelled.withLock { $0 } }
    func cancel() {
        if cm == .nonCancellable { return }
        _isCancelled.withLock { $0 = true }
    }

    let cm: CancellationMode
    init(_ cm: CancellationMode) { self.cm = cm }

    static let cancelled: RunLoopJob = RunLoopJob(.cancellable).apply { $0.cancel() }

    func checkCancellation() throws(CancellationError) {
        if cm == .cancellable && isCancelled {
            throw CancellationError()
        }
    }
}
