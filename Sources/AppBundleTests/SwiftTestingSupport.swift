import Common
import Foundation
import Synchronization
import Testing

// Migrating an XCTest class to Swift Testing:
// - `import XCTest` -> `import Testing` (plus `import AppKit` if the file used AppKit types that XCTest re-exported)
// - `final class FooTest: XCTestCase` -> `@Suite(.aeroSpaceGlobalState) struct FooTest` (keep `@MainActor`; drop
//   `.aeroSpaceGlobalState` only if the suite can't touch the global state at all). `AeroSpaceTestSuite` provides
//   XCTest's `name` for the tests that use it as a workspace name
// - drop `override func setUp() async throws { setUpWorkspacesForTests() }`
// - add `@Test` on its own line above every test function, `@Test(arguments:)` for the cases of a table
// - `XCTAssert*`/`XCTFail` and the helpers in assert.swift -> `#expect` or `#require`
// - run commands with `runCmd` (testUtil.swift), build and check trees with the tree DSL (treeDsl.swift)

/// Swift Testing counterpart of XCTest's `override func setUp() async throws { setUpWorkspacesForTests() }`.
///
/// AeroSpace keeps its model in `@MainActor` globals. Swift Testing runs tests in parallel, and `@MainActor` async tests
/// of different suites interleave at suspension points (`.serialized` only serializes the tests of one suite).
/// The trait gives every test case exclusive access to the global state and resets the state before it runs.
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

/// `isUnitTest` looks this class up by name: it marks the test process for both XCTest and Swift Testing runs
// periphery:ignore - only referenced by its Objective-C name
@objc(AeroSpaceUnitTestMarker)
final class AeroSpaceUnitTestMarker: NSObject {}

/// Provides `name` for suites migrated from XCTest
protocol AeroSpaceTestSuite {}

extension AeroSpaceTestSuite {
    /// Same format as `XCTestCase.name` (`-[AppBundleTests.FooTest testBar]`), so a migrated test uses the same
    /// workspace names as before (the tests use it as a unique workspace name)
    var name: String {
        let testName = Test.current.orDie("'name' is only available while a test is running").name
        return "-[AppBundleTests.\(Self.self) \(testName.hasSuffix("()") ? String(testName.dropLast(2)) : testName)]"
    }
}

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
