@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct MoveWithMouseTest: AeroSpaceTestSuite {
    @Test
    func draggingFloatingWindowWithinItsWorkspaceKeepsItsPlace() async throws {
        let workspace = Workspace.get(byName: name)
        #expect(workspace.focusWorkspace())
        let floating = workspace.floatingWindowsContainer
        let dragged = TestWindow.new(id: 1, parent: floating, rect: Rect(topLeftX: 100, topLeftY: 100, width: 300, height: 200))
        let other = TestWindow.new(id: 2, parent: floating, rect: Rect(topLeftX: 500, topLeftY: 500, width: 300, height: 200))

        try await moveWithMouse(dragged) // Every mouse event of the drag gets here

        #expect(floating.children == [dragged, other])
        #expect(floating.mostRecentChild == other)
    }

    @Test
    func draggingFloatingWindowOntoAnotherWorkspaceMovesItThere() async throws {
        // There is only one test monitor. A window of an invisible workspace stands in for a window that was dragged
        // onto a monitor that shows another workspace
        let visible = Workspace.get(byName: name)
        #expect(visible.focusWorkspace())
        let window = TestWindow.new(
            id: 1,
            parent: Workspace.get(byName: "invisible").floatingWindowsContainer,
            rect: Rect(topLeftX: 100, topLeftY: 100, width: 300, height: 200),
        )

        try await moveWithMouse(window)

        #expect(window.nodeWorkspace == visible)
        #expect(window.isFloating)
    }
}
