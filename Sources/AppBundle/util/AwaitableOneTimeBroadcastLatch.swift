import Common
import Foundation

actor AwaitableOneTimeBroadcastLatch {
    private enum Awaiter {
        case suspended(CheckedContinuation<Void, any Error>)
        /// The client must be cancelled right away when it suspends
        case cancelledBeforeSuspension
    }

    private var isSignaled = false
    private var awaiters: [Int: Awaiter] = [:]
    private var nextAwaiterId = 0

    func await() async throws {
        try checkCancellation()
        if isSignaled { return }

        let id = nextAwaiterId
        nextAwaiterId += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
                switch awaiters.removeValue(forKey: id) {
                    case .cancelledBeforeSuspension: cont.resume(throwing: CancellationError())
                    case .suspended: die("Awaiter \(id) is already suspended")
                    case nil where isSignaled: cont.resume()
                    case nil: awaiters[id] = .suspended(cont)
                }
            }
        } onCancel: {
            Task.startUnstructured { await self.cancel(id: id) }
        }
    }

    private func cancel(id: Int) {
        switch awaiters.removeValue(forKey: id) {
            case .suspended(let cont): cont.resume(throwing: CancellationError())
            case .cancelledBeforeSuspension: die("Awaiter \(id) is already cancelled")
            case nil where !isSignaled: awaiters[id] = .cancelledBeforeSuspension
            case nil: break
        }
    }

    func signalToAll() {
        isSignaled = true
        for case .suspended(let cont) in awaiters.values {
            cont.resume()
        }
        awaiters = [:]
    }
}
