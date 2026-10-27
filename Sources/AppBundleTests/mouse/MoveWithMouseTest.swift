@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct MoveWithMouseTest {
    @Test
    func draggingFloatingWindowWithinItsWorkspaceKeepsItsPlace() async throws {
        let workspace = Workspace.get(byName: "a")
        #expect(workspace.focusWorkspace())
        let floating = workspace.containerCreatingIfNeeded(.floating)
        let dragged = TestWindow.new(id: 1, parent: floating, rect: Rect(topLeftX: 100, topLeftY: 100, width: 300, height: 200))
        let other = TestWindow.new(id: 2, parent: floating, rect: Rect(topLeftX: 500, topLeftY: 500, width: 300, height: 200))

        try await moveWithMouse(dragged) // Every mouse event of the drag gets here

        expectEqual(floating.children, [dragged, other])
        expectEqual(floating.mostRecentChild, other)
    }

    @Test
    func draggingFloatingWindowOntoAnotherMonitorMovesItThereWithTheFocus() async throws {
        fake.monitorInfos = [testMonitor, rightTestMonitor]
        updateMonitors()
        let right = Workspace.get(byName: "right")
        #expect(rightTestMonitor.setActiveWorkspace(right))
        setUpTree("h_tiles(2) floating(*1)")
        let window = testWindow(1)
        window.rect = Rect(topLeftX: 2000, topLeftY: 100, width: 300, height: 200) // Its center is on the right monitor

        try await moveWithMouse(window)

        expectEqual(window.nodeWorkspace, right)
        #expect(window.isFloating)
        expectEqual(focus.windowOrNil?.windowId, 1) // Not the tile 2 that it left
    }

    @Test
    func aWindowThatStopsFloatingDuringTheDragStaysTiling() async throws { // RB-87
        let visible = Workspace.get(byName: "a")
        #expect(visible.focusWorkspace())
        let invisible = Workspace.get(byName: "invisible")
        let window = TestWindow.new(
            id: 1,
            parent: invisible.containerCreatingIfNeeded(.floating),
            rect: Rect(topLeftX: 100, topLeftY: 100, width: 300, height: 200),
        )
        // `layout tiling` runs while the drag reads the window's frame
        fake.onRead = { if $0 == .observedRect(1) { window.relayoutWindow(on: invisible, as: .window) } }

        try await moveWithMouse(window)

        expectEqual(window.nodeWorkspace, invisible)
        #expect(!window.isFloating)
    }
}
