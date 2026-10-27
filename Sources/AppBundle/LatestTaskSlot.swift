import Common

/// Keeps only the most recently started task alive. Starting a new task cancels the previous one. See the table in
/// Sessions.swift
final class LatestTaskSlot {
    private var task: Task<(), any Error>? = nil

    func replace(with operation: @escaping @MainActor () async throws -> ()) {
        task?.cancel()
        task = Task.startUnstructured(operation)
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
