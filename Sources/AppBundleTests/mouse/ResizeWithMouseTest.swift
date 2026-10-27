@testable import AppBundle
import AppKit
import Common
import Testing

/// Resizing and moving a tile with the mouse: the AX events of the drag (``Sessions/onAxEvent(_:)``), then the mouse up
@Suite(.aeroSpaceGlobalState)
struct ResizeWithMouseTest {
    @Test
    func resizingATileWithTheMouseChangesTheWeightsUntilTheMouseUp() async throws {
        await layOutTwoTiles()

        await drag(1, to: rect(0, 0, 1060, 1079), .resized(windowId: 1)) // The right edge, 100 pt to the right
        expectEqual(world.mouseManipulatedWindowId, 1)
        expectEqual(describeTree(weights: true), "h_tiles(*1:1060 2:860)")
        expectEqual(testWindow(2).rect, rect(1060, 0, 860, 1079))

        try await releaseTheMouse()
        expectEqual(world.mouseManipulatedWindowId, nil)
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
    for _ in 0 ..< 100 where world.mouseManipulatedWindowId == nil { await Task.yield() }
    await untilTheHeavyRefreshEnds()
}

private func releaseTheMouse() async throws {
    fake.isLeftMouseDown = false
    try await world.sessions.onLeftMouseUp()
    await untilTheHeavyRefreshEnds()
}

private func untilTheHeavyRefreshEnds() async {
    for _ in 0 ..< 100 where !world.sessions.isHeavyIdle { await Task.yield() }
}
