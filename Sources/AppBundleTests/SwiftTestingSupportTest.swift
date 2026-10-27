@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct SwiftTestingSupportTest {
    // The cases of a parameterized test run in parallel. Each case must see the reset state, and no other test may
    // change the state while this one is suspended
    @Test(arguments: ["a", "b", "c"])
    func testGlobalStateIsIsolated(workspaceName: String) async throws {
        try await assertGlobalStateIsIsolated(workspaceName)
    }

    @Test(.aeroSpaceGlobalState) // Applied twice: must not deadlock
    func testTraitIsReentrant() {
        expectEqual(focus.workspace.name, "setUpWorkspacesForTests")
    }
}

// A second suite: tests of different suites run in parallel too
@Suite(.aeroSpaceGlobalState)
struct SwiftTestingSupportSecondSuiteTest {
    @Test(arguments: ["d", "e"])
    func testGlobalStateIsIsolated(workspaceName: String) async throws {
        try await assertGlobalStateIsIsolated(workspaceName)
    }
}

// No global state trait (it checks isUnitTest itself)
@Suite
struct IsUnitTestTest {
    @Test
    func testIsUnitTest() {
        #expect(isUnitTest)
    }
}

private func assertGlobalStateIsIsolated(_ workspaceName: String) async throws {
    expectEqual(focus.workspace.name, "setUpWorkspacesForTests")
    #expect(Workspace.get(byName: workspaceName).focusWorkspace())
    try await Task.sleep(for: .milliseconds(20))
    expectEqual(focus.workspace.name, workspaceName)
}
