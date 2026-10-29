@testable import AppBundle
import AppKit
import Common
import Testing

/// Resizing and moving a window with the mouse: the AX events of the drag (``Sessions/onAxEvent(_:)``), then the mouse up
@Suite(.aeroSpaceGlobalState)
struct ResizeWithMouseTest {
    @Test
    func resizingATileWithTheMouseChangesTheWeightsUntilTheMouseUp() async throws {
        await layOutTwoTiles()

        await drag(1, to: rect(0, 0, 1060, 1079), .resized(windowId: 1)) // The right edge, 100 pt to the right
        expectEqual(world.mouseManipulatedWindowId, 1)
        expectEqual(describeTree(weights: true), "h_tiles(*1:1060 2:860)")
        expectEqual(testWindow(2).rect, rect(1060, 0, 860, 1079))

        fake.resetCalls()
        try await releaseTheMouse()
        expectEqual(world.mouseManipulatedWindowId, nil)
        // The drag's last read found 1 where the mouse up's layout puts it: each tile is read and neither is written
        let placementCalls: [PlatformCall] = fake.calls.filter { $0.kind == .axRead || $0.kind == .frame }
        expectEqual(placementCalls, [.axRead(1), .axRead(2)])
        // The next resize starts from the new tiles: the weights before the first resize are forgotten (1010 and 910)
        await drag(1, to: rect(0, 0, 1110, 1079), .resized(windowId: 1))
        expectEqual(describeTree(weights: true), "h_tiles(*1:1110 2:810)")
    }

    @Test
    func draggingATileOntoAnotherSwapsThem() async throws {
        await layOutTwoTiles()
        fake.mouseLocation = CGPoint(x: 1500, y: 500)

        await drag(1, to: rect(540, 0, 960, 1079), .moved(windowId: 1))
        expectEqual(describeTree(), "h_tiles(2 *1)")
        expectEqual(testWindow(1).rect, rect(540, 0, 960, 1079)) // The layout leaves it to the mouse
        expectEqual(testWindow(2).rect, rect(0, 0, 960, 1079))

        try await releaseTheMouse()
        expectEqual(testWindow(1).rect, rect(960, 0, 960, 1079))
    }

    /// A tile dragged onto another monitor goes into the workspace there: next to the tile under the mouse, on the
    /// mouse's side of its center, or into the root of an empty workspace. It keeps the focus, and the mouse up lays it
    /// out there
    @Test(arguments: [
        ("h_tiles(3 4)", 3500, "h_tiles(3 4 *1)", rect(3200, 0, 640, 1079)),
        ("h_tiles(3 4)", 3000, "h_tiles(3 *1 4)", rect(2560, 0, 640, 1079)),
        ("", 3000, "h_tiles(*1)", rect(1920, 0, 1920, 1079)),
    ] as [(String, CGFloat, String, Rect)])
    func draggingATileOntoAnotherMonitorMovesItThere(
        rightBefore: String,
        mouseX: CGFloat,
        rightAfter: String,
        frame: Rect,
    ) async throws {
        fake.monitorInfos = [testMonitor, rightTestMonitor]
        updateMonitors()
        let right = Workspace.get(byName: "right")
        #expect(rightTestMonitor.setActiveWorkspace(right))
        setUpTree(rightBefore, workspace: right.name)
        let left = setUpTree("h_tiles(*1 2)")
        fake.focused = 1
        await Reconcile.heavy(.ax("test"))
        fake.mouseLocation = CGPoint(x: mouseX, y: 500)
        fake.resetCalls()

        await drag(1, to: rect(mouseX - 480, 0, 960, 1079), .moved(windowId: 1))
        expectEqual(describeTree(left.name), "h_tiles(2)")
        expectEqual(describeTree(right.name), rightAfter)

        try await releaseTheMouse()
        expectEqual(testWindow(1).rect, frame)
        expectEqual(fake.calls(of: .focus), []) // macOS focuses it already. The tile that it left never gets the focus
    }

    /// A floating window's center crosses the monitors' edge before the mouse does (x 1800), or with it (x 2100). The
    /// window stays on its workspace until the mouse up: on-focused-monitor-changed's `move-mouse monitor-lazy-center`
    /// doesn't warp the mouse that the user holds, and the layout leaves the window where the mouse puts it. The mouse up
    /// moves it to the monitor of its center, where it keeps the focus, and the mouse follows it there if it isn't there
    @Test(arguments: [
        (1800, [.warpMouse(CGPoint(x: 2880, y: 540))]),
        (2100, []),
    ] as [(CGFloat, [PlatformCall])])
    func draggingAFloatingWindowAcrossTheMonitorsEdgeWarpsTheMouseOnlyOnceItsUp(
        mouseX: CGFloat,
        warps: [PlatformCall],
    ) async throws {
        fake.monitorInfos = [testMonitor, rightTestMonitor]
        updateMonitors()
        let right = Workspace.get(byName: "right")
        #expect(rightTestMonitor.setActiveWorkspace(right))
        let left = setUpTree("h_tiles(2) floating(*1)")
        world.config.onFocusedMonitorChanged = parseCommand("move-mouse monitor-lazy-center").cmdOrDie
        testWindow(1).rect = rect(1500, 100, 300, 200)
        fake.focused = 1
        await Reconcile.heavy(.ax("test"))
        fake.mouseLocation = CGPoint(x: mouseX, y: 150)
        fake.resetCalls()

        await drag(1, to: rect(1780, 100, 300, 200), .moved(windowId: 1)) // Its center is at x 1930
        expectEqual(fake.calls(of: .warpMouse), [])
        expectEqual(testWindow(1).nodeWorkspace, left)

        try await releaseTheMouse()
        expectEqual(fake.calls(of: .warpMouse), warps)
        expectEqual(fake.frames(of: 1), [])
        expectEqual(testWindow(1).nodeWorkspace, right)
        expectEqual(focus.windowOrNil?.windowId, 1)
        expectEqual(fake.focused, 1)
    }
}

/// h_tiles(*1 2) on the 1920x1080 test monitor, laid out
private func layOutTwoTiles() async {
    setUpTree("h_tiles(*1 2)")
    testWindow(1).rect = rect(0, 0, 960, 1079)
    testWindow(2).rect = rect(960, 0, 960, 1079)
    fake.focused = 1
    await Reconcile.heavy(.ax("test"))
}

/// The user drags `id` to `frame` with the left mouse button, and macOS reports `event`. Returns once the drag's light
/// session and its heavy refresh have presented
private func drag(_ id: WindowId, to frame: Rect, _ event: AxEvent) async {
    fake.isLeftMouseDown = true
    testWindow(id).rect = frame
    await world.sessions.onAxEvent(event)
    for _ in 0 ..< 100 where world.mouseManipulatedWindowId == nil && world.draggedFloatingWindow == nil { await Task.yield() }
    await untilHeavyIdle()
}

private func releaseTheMouse() async throws {
    fake.isLeftMouseDown = false
    try await world.sessions.onLeftMouseUp()
    await untilHeavyIdle()
}
