@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct WorkspaceBackAndForthCommandTest: AeroSpaceTestSuite {
    @Test
    func testFocusesPrevWorkspace() async {
        _ = Workspace.get(byName: "b")
        assertTrue(Workspace.get(byName: "a").focusWorkspace())
        _prevFocusedWorkspaceName = "b"

        await assertRun("workspace-back-and-forth", exitCode: 0, stdout: [], stderr: [])
        assertEquals(focus.workspace.name, "b")
    }

    @Test
    func testFailsWhenFocusingPrevWorkspaceFails() async {
        // RB-31: the command used to exit 0 whenever there was a previous workspace, even if focusing it failed
        _ = Workspace.get(byName: "b")
        assertTrue(Workspace.get(byName: "a").focusWorkspace())
        _prevFocusedWorkspaceName = "b"

        await $noScreensForTests.withValue(true) {
            // Without screens, only visible workspaces can be focused, and "b" is hidden
            let result = await parseCommand("workspace-back-and-forth").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertNotEquals(result.exitCode.rawValue, 0)
        }
        assertEquals(focus.workspace.name, "a")
    }

    @Test
    func testNoPrevWorkspace_failsWithMessage() async {
        // RB-31: the command used to fail silently
        assertTrue(Workspace.get(byName: "a").focusWorkspace())
        assertNil(prevFocusedWorkspace)

        await assertRun("workspace-back-and-forth", exitCode: 2, stdout: [], stderr: ["There is no previously focused workspace"])
        assertEquals(focus.workspace.name, "a")
    }
}
