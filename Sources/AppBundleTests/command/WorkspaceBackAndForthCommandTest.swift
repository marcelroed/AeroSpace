@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct WorkspaceBackAndForthCommandTest {
    @Test
    func focusesThePreviousWorkspace() async {
        _ = Workspace.get(byName: "b") // Alive
        #expect(Workspace.get(byName: "a").focusWorkspace())
        world.focusStore.prevWorkspaceName = "b"

        let output = await runCmd("workspace-back-and-forth")
        expectEqual(output, .ok)
        expectEqual(focus.workspace.name, "b")
    }

    @Test
    func failsWhenFocusingThePreviousWorkspaceFails() async {
        // RB-31: the command used to exit 0 whenever there was a previous workspace, even if focusing it failed
        _ = Workspace.get(byName: "b") // Alive
        #expect(Workspace.get(byName: "a").focusWorkspace())
        world.focusStore.prevWorkspaceName = "b"

        // Without screens, only visible workspaces can be focused, and "b" is hidden
        let output = await $noScreensForTests.withValue(true) { await runCmd("workspace-back-and-forth") }
        expectEqual(output, .fail()) // todo: without a message
        expectEqual(focus.workspace.name, "a")
    }

    @Test
    func noPreviousWorkspace_failsWithMessage() async {
        // RB-31: the command used to fail silently
        #expect(Workspace.get(byName: "a").focusWorkspace())
        expectEqual(prevFocusedWorkspace, nil)

        let output = await runCmd("workspace-back-and-forth")
        expectEqual(output, .fail("There is no previously focused workspace"))
        expectEqual(focus.workspace.name, "a")
    }
}
