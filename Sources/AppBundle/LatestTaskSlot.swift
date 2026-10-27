import Common

/// Keeps only the most recently started task alive. Starting a new task cancels the previous one
final class LatestTaskSlot {
    private var task: Task<(), any Error>? = nil

    nonisolated init() {}

    func replace(with operation: @escaping @MainActor () async throws -> ()) {
        task?.cancel()
        task = Task.startUnstructured(operation)
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
