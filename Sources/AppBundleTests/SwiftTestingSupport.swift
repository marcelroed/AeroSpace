import Common
import Foundation
import Synchronization
import Testing

/// AeroSpace keeps its model in `@MainActor` globals. Swift Testing runs tests in parallel, and `@MainActor` async tests
/// of different suites interleave at suspension points (`.serialized` only serializes the tests of one suite).
/// The trait gives every test case exclusive access to the global state and resets it (`setUpWorkspacesForTests`)
/// before the test runs.
nonisolated struct AeroSpaceGlobalStateTrait: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true } // Provide the scope for every test case of the suite, including nested suites

    @concurrent
    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @concurrent @Sendable () async throws -> Void,
    ) async throws {
        if GlobalStateLock.isHeldByCurrentTask { // The trait is applied both to a suite and to its test
            try await function()
            return
        }
        await globalStateLock.lock()
        defer { globalStateLock.unlock() }
        await MainActor.run {
            check(isUnitTest, "isUnitTest must be true, otherwise the tests talk to the real macOS windows and monitors")
            setUpWorkspacesForTests()
        }
        try await GlobalStateLock.$isHeldByCurrentTask.withValue(true) {
            try await function()
        }
    }
}

extension Trait where Self == AeroSpaceGlobalStateTrait {
    /// Run every test case of the suite exclusively, with the global state reset. See ``AeroSpaceGlobalStateTrait``
    static var aeroSpaceGlobalState: Self { Self() }
}

/// `isUnitTest` looks this class up by name: its presence marks the test process
// periphery:ignore - only referenced by its Objective-C name
@objc(AeroSpaceUnitTestMarker)
final class AeroSpaceUnitTestMarker: NSObject {}

nonisolated private let globalStateLock = GlobalStateLock()

/// FIFO async mutex. A blocking lock would block Swift Testing's threads
nonisolated private final class GlobalStateLock: Sendable {
    @TaskLocal static var isHeldByCurrentTask = false

    private let state = Mutex((isLocked: false, waiters: [CheckedContinuation<Void, Never>]()))

    func lock() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let acquired = state.withLock { state in
                if state.isLocked {
                    state.waiters.append(cont)
                    return false
                }
                state.isLocked = true
                return true
            }
            if acquired { cont.resume() }
        }
    }

    func unlock() {
        let next = state.withLock { state in
            if state.waiters.isEmpty {
                state.isLocked = false
                return nil as CheckedContinuation<Void, Never>?
            }
            return state.waiters.removeFirst() // The lock stays locked: the ownership passes to the next waiter
        }
        next?.resume()
    }
}
