import Common

/// Keeps only the most recently started task alive. Starting a new task cancels the previous one. See the table in
/// Sessions.swift
final class LatestTaskSlot {
    private var task: Task<(), any Error>? = nil
    /// Tells the current task from the replaced ones when it returns
    private var generation = 0

    /// No task is scheduled or running. A cancelled task may still run
    var isIdle: Bool { task == nil }

    func replace(with operation: @escaping @MainActor () async throws -> ()) {
        task?.cancel()
        generation += 1
        let generation = generation
        task = Task.startUnstructured { [self] in
            defer { if self.generation == generation { task = nil } }
            try await operation()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
