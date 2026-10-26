@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct SwiftTestingSupportTest: AeroSpaceTestSuite {
    // The cases of a parameterized test run in parallel. Each case must see the reset state, and no other test may
    // change the state while this one is suspended
    @Test(arguments: ["a", "b", "c"])
    func testGlobalStateIsIsolated(workspaceName: String) async throws {
        try await assertGlobalStateIsIsolated(workspaceName)
    }

    @Test(.aeroSpaceGlobalState) // Applied twice: must not deadlock
    func testTraitIsReentrant() {
        assertEquals(focus.workspace.name, "setUpWorkspacesForTests")
    }

    @Test
    func testName() {
        assertEquals(name, "-[AppBundleTests.SwiftTestingSupportTest testName]")
    }
}

// A second suite: tests of different suites run in parallel too
@MainActor
@Suite(.aeroSpaceGlobalState)
struct SwiftTestingSupportSecondSuiteTest {
    @Test(arguments: ["d", "e"])
    func testGlobalStateIsIsolated(workspaceName: String) async throws {
        try await assertGlobalStateIsIsolated(workspaceName)
    }
}

// No global state trait: XCTest isn't needed to run Swift Testing tests, but isUnitTest detects tests by XCTest
@Suite
struct IsUnitTestTest {
    @Test
    func testIsUnitTest() {
        assertTrue(isUnitTest)
    }
}

@MainActor
private func assertGlobalStateIsIsolated(_ workspaceName: String) async throws {
    assertEquals(focus.workspace.name, "setUpWorkspacesForTests")
    assertTrue(Workspace.get(byName: workspaceName).focusWorkspace())
    try await Task.sleep(for: .milliseconds(20))
    assertEquals(focus.workspace.name, workspaceName)
}
