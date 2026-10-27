import Dispatch

/// Completed on an AX thread
nonisolated final class CompletableFuture<T: Sendable>: Sendable {
    nonisolated(unsafe) private var value: T?
    private let semaphore = DispatchSemaphore(value: 0)

    func complete(_ t: T) {
        unsafe value = t
        semaphore.signal()
    }

    /// nil if the future isn't completed by the deadline
    func blockingGet(deadline: DispatchTime) -> T? {
        guard semaphore.wait(timeout: deadline) == .success else { return nil }
        return unsafe value.orDie("semaphore should have been signaled")
    }
}
