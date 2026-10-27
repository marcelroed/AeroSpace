@testable import AppBundle
import AppKit
import Common
import Testing

// Characterization tests for layoutRecursive.swift. The test monitor is 1920x1080 at (0, 0)
@MainActor
@Suite(.aeroSpaceGlobalState)
struct LayoutTest: AeroSpaceTestSuite {
    @Test
    func testTilesHorizontal() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let windows = (0 ..< 3).map { TestWindow.new(id: UInt32($0), parent: root) }

        try await workspace.layoutWorkspace()

        assertRects(workspace, physical: rect(0, 0, 1920, 1079), virtual: rect(0, 0, 1920, 1080))
        assertRects(root, physical: rect(0, 0, 1920, 1079), virtual: rect(0, 0, 1920, 1080))
        for (i, window) in windows.enumerated() {
            let x = CGFloat(640 * i)
            assertEquals(window.setAxFrameHistory, [frame(x, 0, 640, 1079)])
            assertRects(window, physical: rect(x, 0, 640, 1079), virtual: rect(x, 0, 640, 1080))
            assertEquals(window.hWeight, 640)
        }
    }

    @Test
    func testTilesNestedWithGaps() async throws {
        config.gaps = Gaps(inner: .init(vertical: 10, horizontal: 20), outer: .init(left: 10, bottom: 19, top: 20, right: 10))
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let w1 = TestWindow.new(id: 1, parent: root, adaptiveWeight: 450)
        let container = TilingContainer.newVTiles(parent: root, adaptiveWeight: 1050)
        let w2 = TestWindow.new(id: 2, parent: container, adaptiveWeight: 1)
        let w3 = TestWindow.new(id: 3, parent: container, adaptiveWeight: 3)

        try await workspace.layoutWorkspace()

        assertRects(workspace, physical: rect(10, 20, 1900, 1040), virtual: rect(10, 20, 1900, 1041))
        assertRects(root, physical: rect(10, 20, 1900, 1040), virtual: rect(10, 20, 1900, 1041))

        assertEquals(w1.setAxFrameHistory, [frame(10, 20, 640, 1040)])
        assertRects(w1, physical: rect(10, 20, 640, 1040), virtual: rect(10, 20, 650, 1041))
        assertEquals(w1.hWeight, 650)

        assertRects(container, physical: rect(670, 20, 1240, 1040), virtual: rect(660, 20, 1250, 1041))
        assertEquals(container.hWeight, 1250)

        assertEquals(w2.setAxFrameHistory, [frame(670, 20, 1240, 514)])
        assertRects(w2, physical: rect(670, 20, 1240, 514), virtual: rect(660, 20, 1250, 519)) // The virtual width of the container
        assertEquals(w2.vWeight, 519)

        assertEquals(w3.setAxFrameHistory, [frame(670, 544, 1240, 516)])
        assertRects(w3, physical: rect(670, 544, 1240, 516), virtual: rect(660, 539, 1250, 521))
        assertEquals(w3.vWeight, 521)
    }

    @Test
    func testTilesPerMonitorGaps() async throws {
        let main = [PerMonitorValue(description: .main, value: 100)]
        let secondary = [PerMonitorValue(description: .secondary, value: 100)]
        config.gaps = Gaps(
            inner: .init(vertical: .constant(0), horizontal: .perMonitor([PerMonitorValue(description: .main, value: 40)], default: 0)),
            outer: .init(left: .perMonitor(main, default: 0), bottom: .constant(0), top: .constant(0), right: .perMonitor(secondary, default: 20)),
        )
        let workspace = Workspace.get(byName: name)
        let w1 = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let w2 = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)

        try await workspace.layoutWorkspace()

        assertRects(workspace, physical: rect(100, 0, 1800, 1079), virtual: rect(100, 0, 1800, 1080))
        assertEquals(w1.setAxFrameHistory, [frame(100, 0, 880, 1079)])
        assertEquals(w2.setAxFrameHistory, [frame(1020, 0, 880, 1079)])
        assertRects(w2, physical: rect(1020, 0, 880, 1079), virtual: rect(1000, 0, 900, 1080))
    }

    @Test
    func testAccordionHorizontal() async throws {
        config.accordionPadding = 30
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        root.layout = .accordion
        let windows = (0 ..< 3).map { TestWindow.new(id: UInt32($0), parent: root) }

        // MRU is the first child
        windows[0].markAsMostRecentChild()
        try await workspace.layoutWorkspace()
        assertEquals(windows.map(\.setAxFrameHistory.last), [
            frame(0, 0, 1890, 1079),
            frame(60, 0, 1860, 1079),
            frame(30, 0, 1890, 1079),
        ])

        // MRU is the middle child
        windows[1].markAsMostRecentChild()
        try await workspace.layoutWorkspace()
        assertEquals(windows.map(\.setAxFrameHistory.last), [
            frame(0, 0, 1890, 1079),
            frame(30, 0, 1860, 1079),
            frame(30, 0, 1890, 1079),
        ])

        // MRU is the last child
        windows[2].markAsMostRecentChild()
        try await workspace.layoutWorkspace()
        assertEquals(windows.map(\.setAxFrameHistory.last), [
            frame(0, 0, 1890, 1079),
            frame(0, 0, 1860, 1079),
            frame(30, 0, 1890, 1079),
        ])

        assertRects(root, physical: rect(0, 0, 1920, 1079), virtual: rect(0, 0, 1920, 1080))
        for window in windows {
            assertEquals(window.setAxFrameHistory.count, 3)
            assertEquals(window.lastAppliedLayoutVirtualRect.map(cg), rect(0, 0, 1920, 1080))
        }
        assertRects(windows[1], physical: rect(0, 0, 1860, 1079), virtual: rect(0, 0, 1920, 1080))
    }

    @Test
    func testAccordionVertical() async throws {
        config.accordionPadding = 30
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        root.layout = .accordion
        root.changeOrientation(.v)
        let windows = (0 ..< 4).map { TestWindow.new(id: UInt32($0), parent: root) }
        windows[1].markAsMostRecentChild()

        try await workspace.layoutWorkspace()

        assertEquals(windows.map(\.setAxFrameHistory), [
            [frame(0, 0, 1920, 1049)],
            [frame(0, 30, 1920, 1019)],
            [frame(0, 60, 1920, 1019)],
            [frame(0, 30, 1920, 1049)],
        ])
    }

    @Test
    func testAccordionSingleChild() async throws {
        config.accordionPadding = 30
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.layout = .accordion
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)

        try await workspace.layoutWorkspace()

        assertEquals(window.setAxFrameHistory, [frame(0, 0, 1920, 1079)])
    }

    @Test
    func testAccordionInsideTiles() async throws {
        config.accordionPadding = 10
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let w1 = TestWindow.new(id: 1, parent: root)
        let accordion = TilingContainer(parent: root, adaptiveWeight: 1, .v, .accordion, index: INDEX_BIND_LAST)
        let w2 = TestWindow.new(id: 2, parent: accordion)
        let w3 = TestWindow.new(id: 3, parent: accordion)

        try await workspace.layoutWorkspace()

        assertEquals(w1.setAxFrameHistory, [frame(0, 0, 960, 1079)])
        assertRects(accordion, physical: rect(960, 0, 960, 1079), virtual: rect(960, 0, 960, 1080))
        assertEquals(w2.setAxFrameHistory, [frame(960, 0, 960, 1069)])
        assertEquals(w3.setAxFrameHistory, [frame(960, 10, 960, 1069)])
        assertRects(w3, physical: rect(960, 10, 960, 1069), virtual: rect(960, 0, 960, 1080))
    }

    @Test
    func testFullscreenTilingWindow() async throws {
        config.gaps = Gaps(inner: .zero, outer: .init(left: 5, bottom: 5, top: 5, right: 5))
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let w1 = TestWindow.new(id: 1, parent: root)
        let w2 = TestWindow.new(id: 2, parent: root) // MRU
        w2.isFullscreen = true

        try await workspace.layoutWorkspace()
        assertEquals(w1.setAxFrameHistory, [frame(5, 5, 955, 1069)])
        assertEquals(w2.setAxFrameHistory, [frame(5, 5, 1910, 1070)])
        assertNil(w2.lastAppliedLayoutPhysicalRect)
        assertEquals(w2.lastAppliedLayoutVirtualRect.map(cg), rect(960, 5, 955, 1070))
        assertTrue(w2.isFullscreen)

        w2.noOuterGapsInFullscreen = true
        try await workspace.layoutWorkspace()
        assertEquals(w2.setAxFrameHistory.last, frame(0, 0, 1920, 1080))

        // Only the MRU window can be fullscreen
        w1.isFullscreen = true
        try await workspace.layoutWorkspace()
        assertFalse(w1.isFullscreen)
        assertEquals(w1.setAxFrameHistory.last, frame(5, 5, 955, 1069))
        assertRects(w1, physical: rect(5, 5, 955, 1069), virtual: rect(5, 5, 955, 1070))
    }

    @Test
    func testFloatingWindows() async throws {
        let workspace = Workspace.get(byName: name) // Not the active workspace of the monitor
        let floating = workspace.floatingWindowsContainer
        let centered = TestWindow.new(id: 1, parent: floating, rect: rect(960, 540, 300, 200))
        let outside = TestWindow.new(id: 2, parent: floating, rect: rect(1800, 1000, 300, 200))
        let noRect = TestWindow.new(id: 3, parent: floating)
        let fullscreen = TestWindow.new(id: 4, parent: floating)
        fullscreen.isFullscreen = true
        centered.lastAppliedLayoutPhysicalRect = rect(1, 2, 3, 4)
        centered.lastAppliedLayoutVirtualRect = rect(1, 2, 3, 4)

        try await workspace.layoutWorkspace()

        assertEquals(centered.setAxFrameHistory, [AxFrame(topLeft: CGPoint(x: 960, y: 540), size: nil)])
        assertEquals(outside.setAxFrameHistory, [AxFrame(topLeft: CGPoint(x: 1620, y: 880), size: nil)])
        assertEquals(noRect.setAxFrameHistory, [])
        assertEquals(fullscreen.setAxFrameHistory, [frame(0, 0, 1920, 1080)])
        assertFalse(fullscreen.isFullscreen)
        assertNil(centered.lastAppliedLayoutPhysicalRect)
        assertNil(centered.lastAppliedLayoutVirtualRect)

        // Floating windows of the active workspace are not moved
        assertTrue(workspace.focusWorkspace())
        try await workspace.layoutWorkspace()
        assertEquals(centered.setAxFrameHistory.count, 1)
        assertEquals(outside.setAxFrameHistory.count, 1)
        assertEquals(fullscreen.setAxFrameHistory.count, 1)
    }

    @Test
    func testWindowManipulatedWithMouseIsSkipped() async throws {
        let workspace = Workspace.get(byName: name)
        let w1 = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let w2 = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        currentlyManipulatedWithMouseWindowId = w1.windowId
        defer { currentlyManipulatedWithMouseWindowId = nil }

        try await workspace.layoutWorkspace()

        assertEquals(w1.setAxFrameHistory, [])
        assertNil(w1.lastAppliedLayoutPhysicalRect)
        assertNil(w1.lastAppliedLayoutVirtualRect)
        assertEquals(w1.hWeight, 960)
        assertEquals(w2.setAxFrameHistory, [frame(960, 0, 960, 1079)])
    }

    @Test
    func testEmptyWorkspaceIsNotLaidOut() async throws {
        let workspace = Workspace.get(byName: name)
        _ = TilingContainer.newVTiles(parent: workspace.rootTilingContainer, adaptiveWeight: 1)

        try await workspace.layoutWorkspace()

        assertNil(workspace.lastAppliedLayoutPhysicalRect)
        assertNil(workspace.rootTilingContainer.lastAppliedLayoutPhysicalRect)
    }

    @Test
    func testNotLookingZoomed() {
        let screen = rect(0, 0, 1920, 1080)
        // A tile that fills the screen keeps its bottom edge 11pt above the screen's
        assertEquals(cg(rect(0, 0, 1920, 1079).notLookingZoomed(in: screen)), rect(0, 0, 1920, 1069))
        assertEquals(cg(rect(10, 10, 1900, 1060).notLookingZoomed(in: screen)), rect(10, 10, 1900, 1059))
        // One edge more than 10pt away is enough
        assertEquals(cg(rect(0, 0, 1920, 1069).notLookingZoomed(in: screen)), rect(0, 0, 1920, 1069))
        assertEquals(cg(rect(0, 0, 960, 1079).notLookingZoomed(in: screen)), rect(0, 0, 960, 1079))
        assertEquals(cg(rect(0, 11, 1920, 1068).notLookingZoomed(in: screen)), rect(0, 11, 1920, 1068))
    }
}

private func frame(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> AxFrame {
    AxFrame(topLeft: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
}

private func cg(_ rect: Rect) -> CGRect {
    CGRect(x: rect.topLeftX, y: rect.topLeftY, width: rect.width, height: rect.height)
}

private func assertEquals(_ actual: CGRect?, _ expected: Rect, fileID: String = #fileID, filePath: StaticString = #filePath, line: Int = #line, column: Int = #column) {
    assertEquals(actual, cg(expected), fileID: fileID, filePath: filePath, line: line, column: column)
}

@MainActor
private func assertRects(_ node: TreeNode, physical: Rect, virtual: Rect, fileID: String = #fileID, filePath: StaticString = #filePath, line: Int = #line, column: Int = #column) {
    assertEquals(node.lastAppliedLayoutPhysicalRect.map(cg), physical, fileID: fileID, filePath: filePath, line: line, column: column)
    assertEquals(node.lastAppliedLayoutVirtualRect.map(cg), virtual, fileID: fileID, filePath: filePath, line: line, column: column)
}
