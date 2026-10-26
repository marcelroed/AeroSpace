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

        assertEquals(
            await parseCommand("workspace-back-and-forth").cmdOrDie.run(.defaultEnv, .emptyStdin),
            CmdResult(stdout: [], stderr: [], exitCode: .succ),
        )
        assertEquals(focus.workspace.name, "b")
    }

    @Test
    func testNoPrevWorkspace_failsWithMessage() async {
        // RB-31: the command used to fail silently
        assertTrue(Workspace.get(byName: "a").focusWorkspace())
        assertNil(prevFocusedWorkspace)

        assertEquals(
            await parseCommand("workspace-back-and-forth").cmdOrDie.run(.defaultEnv, .emptyStdin),
            CmdResult(stdout: [], stderr: ["There is no previously focused workspace"], exitCode: .fail),
        )
        assertEquals(focus.workspace.name, "a")
    }
}
