@testable import AppBundle
import AppKit
import Common
import Testing

// Characterization tests for layout.swift. The test monitor is 1920x1080 at (0, 0). The trees are in workspace
// 'a', which isn't the active workspace of the monitor
@Suite(.aeroSpaceGlobalState)
struct LayoutTest {
    @Test
    func tilesHorizontal() async throws {
        let workspace = setUpTree("h_tiles(0 1 2)", workspace: "a")
        let root = workspace.rootTilingContainer
        let windows = (0 ..< 3).map(testWindow)

        try await workspace.layoutWorkspace()

        expectRects(workspace, physical: rect(0, 0, 1920, 1079), virtual: rect(0, 0, 1920, 1080))
        expectRects(root, physical: rect(0, 0, 1920, 1079), virtual: rect(0, 0, 1920, 1080))
        for (i, window) in windows.enumerated() {
            let x = CGFloat(640 * i)
            expectEqual(window.setAxFrameHistory, [frame(x, 0, 640, 1079)])
            expectRects(window, physical: rect(x, 0, 640, 1079), virtual: rect(x, 0, 640, 1080))
            expectEqual(window.hWeight, 640)
        }
    }

    @Test
    func tilesNestedWithGaps() async throws {
        world.config.gaps = Gaps(inner: .init(vertical: 10, horizontal: 20), outer: .init(left: 10, bottom: 19, top: 20, right: 10))
        let workspace = setUpTree("h_tiles(1:450 v_tiles:1050(2:1 3:3))", workspace: "a")
        let root = workspace.rootTilingContainer
        let (w1, w2, w3) = (testWindow(1), testWindow(2), testWindow(3))
        let container = w2.parent.orDie()

        try await workspace.layoutWorkspace()

        expectRects(workspace, physical: rect(10, 20, 1900, 1040), virtual: rect(10, 20, 1900, 1041))
        expectRects(root, physical: rect(10, 20, 1900, 1040), virtual: rect(10, 20, 1900, 1041))

        expectEqual(w1.setAxFrameHistory, [frame(10, 20, 640, 1040)])
        expectRects(w1, physical: rect(10, 20, 640, 1040), virtual: rect(10, 20, 650, 1041))
        expectEqual(w1.hWeight, 650)

        expectRects(container, physical: rect(670, 20, 1240, 1040), virtual: rect(660, 20, 1250, 1041))
        expectEqual(container.hWeight, 1250)

        expectEqual(w2.setAxFrameHistory, [frame(670, 20, 1240, 514)])
        expectRects(w2, physical: rect(670, 20, 1240, 514), virtual: rect(660, 20, 1250, 519)) // The virtual width of the container
        expectEqual(w2.vWeight, 519)

        expectEqual(w3.setAxFrameHistory, [frame(670, 544, 1240, 516)])
        expectRects(w3, physical: rect(670, 544, 1240, 516), virtual: rect(660, 539, 1250, 521))
        expectEqual(w3.vWeight, 521)
    }

    @Test
    func tilesPerMonitorGaps() async throws {
        let main = [PerMonitorValue(description: .main, value: 100)]
        let secondary = [PerMonitorValue(description: .secondary, value: 100)]
        world.config.gaps = Gaps(
            inner: .init(vertical: .constant(0), horizontal: .perMonitor([PerMonitorValue(description: .main, value: 40)], default: 0)),
            outer: .init(left: .perMonitor(main, default: 0), bottom: .constant(0), top: .constant(0), right: .perMonitor(secondary, default: 20)),
        )
        let workspace = setUpTree("h_tiles(1 2)", workspace: "a")
        let (w1, w2) = (testWindow(1), testWindow(2))

        try await workspace.layoutWorkspace()

        expectRects(workspace, physical: rect(100, 0, 1800, 1079), virtual: rect(100, 0, 1800, 1080))
        expectEqual(w1.setAxFrameHistory, [frame(100, 0, 880, 1079)])
        expectEqual(w2.setAxFrameHistory, [frame(1020, 0, 880, 1079)])
        expectRects(w2, physical: rect(1020, 0, 880, 1079), virtual: rect(1000, 0, 900, 1080))
    }

    @Test
    func accordionHorizontal() async throws {
        world.config.accordionPadding = 30
        let workspace = setUpTree("h_accordion(0 1 2)", workspace: "a")
        let root = workspace.rootTilingContainer
        let windows = (0 ..< 3).map(testWindow)

        // MRU is the first child
        windows[0].markAsMostRecentChild()
        try await workspace.layoutWorkspace()
        expectEqual(windows.map(\.setAxFrameHistory.last), [
            frame(0, 0, 1890, 1079),
            frame(60, 0, 1860, 1079),
            frame(30, 0, 1890, 1079),
        ])

        // MRU is the middle child
        windows[1].markAsMostRecentChild()
        try await workspace.layoutWorkspace()
        expectEqual(windows.map(\.setAxFrameHistory.last), [
            frame(0, 0, 1890, 1079),
            frame(30, 0, 1860, 1079),
            frame(30, 0, 1890, 1079),
        ])

        // MRU is the last child
        windows[2].markAsMostRecentChild()
        try await workspace.layoutWorkspace()
        expectEqual(windows.map(\.setAxFrameHistory.last), [
            frame(0, 0, 1890, 1079),
            frame(0, 0, 1860, 1079),
            frame(30, 0, 1890, 1079),
        ])

        expectRects(root, physical: rect(0, 0, 1920, 1079), virtual: rect(0, 0, 1920, 1080))
        for window in windows {
            expectEqual(window.setAxFrameHistory.count, 3)
            expectEqual(window.lastAppliedLayoutVirtualRect.map(cg), cg(rect(0, 0, 1920, 1080)))
        }
        expectRects(windows[1], physical: rect(0, 0, 1860, 1079), virtual: rect(0, 0, 1920, 1080))
    }

    @Test
    func accordionVertical() async throws {
        world.config.accordionPadding = 30
        let workspace = setUpTree("v_accordion(0 1 2 3)", workspace: "a")
        let windows = (0 ..< 4).map(testWindow)
        windows[1].markAsMostRecentChild()

        try await workspace.layoutWorkspace()

        expectEqual(windows.map(\.setAxFrameHistory), [
            [frame(0, 0, 1920, 1049)],
            [frame(0, 30, 1920, 1019)],
            [frame(0, 60, 1920, 1019)],
            [frame(0, 30, 1920, 1049)],
        ])
    }

    @Test
    func accordionSingleChild() async throws {
        world.config.accordionPadding = 30
        let workspace = setUpTree("h_accordion(1)", workspace: "a")
        let window = testWindow(1)

        try await workspace.layoutWorkspace()

        expectEqual(window.setAxFrameHistory, [frame(0, 0, 1920, 1079)])
    }

    @Test
    func accordionInsideTiles() async throws {
        world.config.accordionPadding = 10
        let workspace = setUpTree("h_tiles(1 v_accordion(2 3))", workspace: "a")
        let (w1, w2, w3) = (testWindow(1), testWindow(2), testWindow(3))
        let accordion = w2.parent.orDie()

        try await workspace.layoutWorkspace()

        expectEqual(w1.setAxFrameHistory, [frame(0, 0, 960, 1079)])
        expectRects(accordion, physical: rect(960, 0, 960, 1079), virtual: rect(960, 0, 960, 1080))
        expectEqual(w2.setAxFrameHistory, [frame(960, 0, 960, 1069)])
        expectEqual(w3.setAxFrameHistory, [frame(960, 10, 960, 1069)])
        expectRects(w3, physical: rect(960, 10, 960, 1069), virtual: rect(960, 0, 960, 1080))
    }

    @Test
    func fullscreenTilingWindow() async throws {
        world.config.gaps = Gaps(inner: .zero, outer: .init(left: 5, bottom: 5, top: 5, right: 5))
        let workspace = setUpTree("h_tiles(1 2)", workspace: "a") // 2 is the most recent window
        let (w1, w2) = (testWindow(1), testWindow(2))
        w2.isFullscreen = true

        try await workspace.layoutWorkspace()
        expectEqual(w1.setAxFrameHistory, [frame(5, 5, 955, 1069)])
        expectEqual(w2.setAxFrameHistory, [frame(5, 5, 1910, 1070)])
        expectEqual(w2.lastAppliedLayoutPhysicalRect.map(cg), nil)
        expectEqual(w2.lastAppliedLayoutVirtualRect.map(cg), cg(rect(960, 5, 955, 1070)))
        #expect(w2.isFullscreen)

        w2.noOuterGapsInFullscreen = true
        try await workspace.layoutWorkspace()
        expectEqual(w2.setAxFrameHistory.last, frame(0, 0, 1920, 1080))

        // Only the MRU window can be fullscreen
        w1.isFullscreen = true
        try await workspace.layoutWorkspace()
        #expect(!w1.isFullscreen)
        expectEqual(w1.setAxFrameHistory.last, frame(5, 5, 955, 1069))
        expectRects(w1, physical: rect(5, 5, 955, 1069), virtual: rect(5, 5, 955, 1070))
    }

    @Test
    func floatingWindows() async throws {
        let workspace = setUpTree("h_tiles() floating(1 2 3 4)", workspace: "a")
        let (centered, outside, noRect, fullscreen) = (testWindow(1), testWindow(2), testWindow(3), testWindow(4))
        centered.rect = rect(960, 540, 300, 200)
        outside.rect = rect(1800, 1000, 300, 200)
        fullscreen.isFullscreen = true
        centered.lastAppliedLayoutPhysicalRect = rect(1, 2, 3, 4)
        centered.lastAppliedLayoutVirtualRect = rect(1, 2, 3, 4)

        try await workspace.layoutWorkspace()

        expectEqual(centered.setAxFrameHistory, [AxFrame(topLeft: CGPoint(x: 960, y: 540), size: nil)])
        expectEqual(outside.setAxFrameHistory, [AxFrame(topLeft: CGPoint(x: 1620, y: 880), size: nil)])
        expectEqual(noRect.setAxFrameHistory, [])
        expectEqual(fullscreen.setAxFrameHistory, [frame(0, 0, 1920, 1080)])
        #expect(!fullscreen.isFullscreen)
        expectEqual(centered.lastAppliedLayoutPhysicalRect.map(cg), nil)
        expectEqual(centered.lastAppliedLayoutVirtualRect.map(cg), nil)

        // Floating windows of the active workspace are not moved
        #expect(workspace.focusWorkspace())
        try await workspace.layoutWorkspace()
        expectEqual(centered.setAxFrameHistory.count, 1)
        expectEqual(outside.setAxFrameHistory.count, 1)
        expectEqual(fullscreen.setAxFrameHistory.count, 1)
    }

    @Test
    func windowManipulatedWithMouseIsSkipped() async throws {
        let workspace = setUpTree("h_tiles(1 2)", workspace: "a")
        let (w1, w2) = (testWindow(1), testWindow(2))
        world.mouseManipulatedWindowId = w1.windowId
        defer { world.mouseManipulatedWindowId = nil }

        try await workspace.layoutWorkspace()

        expectEqual(w1.setAxFrameHistory, [])
        expectEqual(w1.lastAppliedLayoutPhysicalRect.map(cg), nil)
        expectEqual(w1.lastAppliedLayoutVirtualRect.map(cg), nil)
        expectEqual(w1.hWeight, 960)
        expectEqual(w2.setAxFrameHistory, [frame(960, 0, 960, 1079)])
    }

    @Test
    func layoutTilingReturnsTheFramesWithoutAxCalls() {
        let workspace = setUpTree("h_tiles(1 v_accordion(2 3) 4) floating(5)", workspace: "a")

        let frames = workspace.layoutTiling()

        expectEqual(frames.map(\.window.windowId), [1, 2, 3, 4]) // Depth first: the order layoutWorkspace applies them in
        expectEqual(frames.first, WindowFrame(window: testWindow(1), topLeft: CGPoint(x: 0, y: 0), size: CGSize(width: 640, height: 1079)))
        expectEqual(frames.last, WindowFrame(window: testWindow(4), topLeft: CGPoint(x: 1280, y: 0), size: CGSize(width: 640, height: 1079)))
        #expect((1 ... 5).allSatisfy { testWindow($0).setAxFrameHistory.isEmpty })
        expectRects(testWindow(4), physical: rect(1280, 0, 640, 1079), virtual: rect(1280, 0, 640, 1080))
        expectEqual(testWindow(4).hWeight, 640)
    }

    @Test
    func emptyWorkspaceIsNotLaidOut() async throws {
        let workspace = setUpTree("h_tiles(v_tiles())", workspace: "a")

        try await workspace.layoutWorkspace()

        expectEqual(workspace.lastAppliedLayoutPhysicalRect.map(cg), nil)
        expectEqual(workspace.rootTilingContainer.lastAppliedLayoutPhysicalRect.map(cg), nil)
    }

    @Test
    func notLookingZoomed() {
        let screen = rect(0, 0, 1920, 1080)
        // A tile that fills the screen keeps its bottom edge 11pt above the screen's
        expectEqual(cg(rect(0, 0, 1920, 1079).notLookingZoomed(in: screen)), cg(rect(0, 0, 1920, 1069)))
        expectEqual(cg(rect(10, 10, 1900, 1060).notLookingZoomed(in: screen)), cg(rect(10, 10, 1900, 1059)))
        // One edge more than 10pt away is enough
        expectEqual(cg(rect(0, 0, 1920, 1069).notLookingZoomed(in: screen)), cg(rect(0, 0, 1920, 1069)))
        expectEqual(cg(rect(0, 0, 960, 1079).notLookingZoomed(in: screen)), cg(rect(0, 0, 960, 1079)))
        expectEqual(cg(rect(0, 11, 1920, 1068).notLookingZoomed(in: screen)), cg(rect(0, 11, 1920, 1068)))
    }
}

private func frame(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> AxFrame {
    AxFrame(topLeft: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
}

private func cg(_ rect: Rect) -> CGRect {
    CGRect(x: rect.topLeftX, y: rect.topLeftY, width: rect.width, height: rect.height)
}

private func expectRects(_ node: TreeNode, physical: Rect, virtual: Rect, sourceLocation: SourceLocation = #_sourceLocation) {
    expectEqual(node.lastAppliedLayoutPhysicalRect.map(cg), cg(physical), sourceLocation: sourceLocation)
    expectEqual(node.lastAppliedLayoutVirtualRect.map(cg), cg(virtual), sourceLocation: sourceLocation)
}
