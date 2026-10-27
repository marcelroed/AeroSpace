import AppKit
import Common

/// A frame for the platform to apply with ``Window/setAxFrame(_:_:)``. Raw: the size may be negative, exactly as the
/// layout arithmetic produces it
struct WindowFrame: Equatable {
    let window: Window
    let topLeft: CGPoint
    let size: CGSize
}

extension Workspace {
    /// Applies the frames of ``layoutTiling()`` in their order, then repositions the floating windows
    func layoutWorkspace() async throws {
        if isEffectivelyEmpty { return }
        for frame in layoutTiling() {
            frame.window.setAxFrame(frame.topLeft, frame.size)
        }
        try await layoutFloatingWindows()
    }

    /// Lays out the tiling tree without AX calls: writes the layout rects and the tiles weights into the tree and returns
    /// the frames of the tiling windows, depth first. Without a root container there are no tiling windows
    func layoutTiling() -> [WindowFrame] {
        let monitor = workspaceMonitor
        let gaps = ResolvedGaps(gaps: config.gaps, monitor: monitor)
        let rect = monitor.visibleRectPadded(by: gaps)
        // If monitors are aligned vertically and the monitor below has smaller width, then macOS may not allow the
        // window on the upper monitor to take full width. rect.height - 1 resolves this problem
        // But I also faced this problem in monitors horizontal configuration. ¯\_(ツ)_/¯
        let height = rect.height - 1
        var physicalRect = rect
        physicalRect.height = height
        lastAppliedLayoutPhysicalRect = physicalRect
        lastAppliedLayoutVirtualRect = rect
        guard let root = existingRootTilingContainer else { return [] }
        let params = LayoutParams(
            monitor: monitor,
            gaps: gaps,
            accordionPadding: CGFloat(config.accordionPadding),
            skippedWindowId: world.mouseManipulatedWindowId,
            fullscreenCandidate: root.mostRecentWindowRecursive,
        )
        var frames: [WindowFrame] = []
        root.layoutTiling(rect.topLeftCorner, width: rect.width, height: height, virtual: rect, params, &frames)
        return frames
    }

    /// Floating windows keep their frame. One that is on a monitor that shows another workspace moves to the same relative
    /// position on its workspace's monitor. Each window's frame is read and then set before the next window's is read
    private func layoutFloatingWindows() async throws {
        for window in floatingWindows {
            window.lastAppliedLayoutPhysicalRect = nil
            window.lastAppliedLayoutVirtualRect = nil
            let windowRect = try await window.getAxRect(.cancellable) // Probably not idempotent
            // The window may have closed or moved at the suspension point above. A dead workspace can't be compared by name
            if !isAlive || window.placement != .floating(self) { continue }
            // The screens may disappear at the suspension point above. Don't move the window to the fake mainMonitorInfo
            if !hasScreens { continue }
            if let windowRect, let topLeft = floatingTopLeft(windowRect) {
                window.setAxFrame(topLeft, nil)
            }
            if window.isFullscreen {
                let frame = window.fullscreenFrame(on: workspaceMonitor)
                window.setAxFrame(frame.topLeft, frame.size)
                window.isFullscreen = false
            }
        }
    }

    /// Where a floating window at `windowRect` moves, nil if it stays: when the monitor it's on shows another workspace, to
    /// the same relative position on this workspace's monitor, clamped to fit
    private func floatingTopLeft(_ windowRect: Rect) -> CGPoint? {
        let currentMonitor = windowRect.center.monitorApproximation
        if self == currentMonitor.activeWorkspace { return nil }
        let xProportion = (windowRect.topLeftX - currentMonitor.visibleRect.topLeftX) / currentMonitor.visibleRect.width
        let yProportion = (windowRect.topLeftY - currentMonitor.visibleRect.topLeftY) / currentMonitor.visibleRect.height

        let workspaceRect = workspaceMonitor.visibleRect
        let x = workspaceRect.topLeftX + xProportion * workspaceRect.width
        let y = workspaceRect.topLeftY + yProportion * workspaceRect.height
        return CGPoint(
            x: x.coerce(in: workspaceRect.minX ... max(workspaceRect.minX, workspaceRect.maxX - windowRect.width)),
            y: y.coerce(in: workspaceRect.minY ... max(workspaceRect.minY, workspaceRect.maxY - windowRect.height)),
        )
    }
}

/// What the tiling layout reads besides the tree. Read once per workspace
private struct LayoutParams {
    let monitor: MonitorInfo
    let gaps: ResolvedGaps
    let accordionPadding: CGFloat
    /// The window that is moved or resized with the mouse. Its frame is left alone
    let skippedWindowId: UInt32?
    /// The root's most recent window: the only one that a `fullscreen` window fills the monitor with
    let fullscreenCandidate: Window?
}

extension TreeNode {
    fileprivate func layoutTiling(
        _ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ params: LayoutParams, _ frames: inout [WindowFrame],
    ) {
        let physicalRect = Rect(topLeftX: point.x, topLeftY: point.y, width: width, height: height)
        switch self {
            case let window as Window:
                if window.windowId == params.skippedWindowId { return }
                lastAppliedLayoutVirtualRect = virtual
                if window.isFullscreen && window == params.fullscreenCandidate {
                    lastAppliedLayoutPhysicalRect = nil
                    frames.append(window.fullscreenFrame(on: params.monitor))
                } else {
                    let rect = window.app.rawAppBundleId == KnownBundleId.cmux.rawValue
                        ? physicalRect.notLookingZoomed(in: params.monitor.visibleRect)
                        : physicalRect
                    lastAppliedLayoutPhysicalRect = rect
                    window.isFullscreen = false
                    frames.append(WindowFrame(window: window, topLeft: rect.topLeftCorner, size: rect.size))
                }
            case let container as TilingContainer:
                lastAppliedLayoutPhysicalRect = physicalRect
                lastAppliedLayoutVirtualRect = virtual
                switch container.layout {
                    case .tiles: container.layoutTiles(point, width: width, height: height, virtual: virtual, params, &frames)
                    case .accordion: container.layoutAccordion(point, width: width, height: height, virtual: virtual, params, &frames)
                }
            default:
                die("A tiling container's child is a window or a tiling container")
        }
    }
}

extension Rect {
    /// cmux snaps a window that looks zoomed to the screen's visible frame whenever cmux is activated. macOS considers a
    /// window zoomed if every edge is within 10pt of the visible frame, and a tile that fills the screen is 1pt shorter
    /// than it (see layoutTiling), so cmux and AeroSpace would resize the window back and forth on every activation.
    /// Such a tile keeps its bottom edge 11pt above the visible frame's instead
    func notLookingZoomed(in visibleRect: Rect) -> Rect {
        let looksZoomed = abs(minX - visibleRect.minX) <= 10 && abs(minY - visibleRect.minY) <= 10
            && abs(maxX - visibleRect.maxX) <= 10 && abs(maxY - visibleRect.maxY) <= 10
        guard looksZoomed else { return self }
        var rect = self
        rect.height = visibleRect.maxY - 11 - minY
        return rect
    }
}

extension Window {
    fileprivate func fullscreenFrame(on monitor: MonitorInfo) -> WindowFrame {
        let rect = noOuterGapsInFullscreen ? monitor.visibleRect : monitor.visibleRectPaddedByOuterGaps
        return WindowFrame(window: self, topLeft: rect.topLeftCorner, size: CGSize(width: rect.width, height: rect.height))
    }
}

extension TilingContainer {
    fileprivate func layoutTiles(
        _ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ params: LayoutParams, _ frames: inout [WindowFrame],
    ) {
        var point = point
        var virtualPoint = virtual.topLeftCorner

        let size: CGFloat = orientation == .h ? width : height
        let weightSum: CGFloat = children.sum { $0.getWeight(orientation) }
        guard let delta = (size - weightSum).div(children.count) else { return }

        let lastIndex = children.indices.last
        let rawGap = Double(params.gaps.inner.get(orientation))
        for (i, child) in children.enumerated() {
            let weight = child.getWeight(orientation) + delta
            child.setWeight(orientation, weight)
            // Gaps. Consider 4 cases:
            // 1. Multiple children. Layout first child
            // 2. Multiple children. Layout last child
            // 3. Multiple children. Layout child in the middle
            // 4. Single child
            let gap = rawGap - (i == 0 ? rawGap / 2 : 0) - (i == lastIndex ? rawGap / 2 : 0)
            child.layoutTiling(
                i == 0 ? point : point.addingOffset(orientation, rawGap / 2),
                width: orientation == .h ? weight - gap : width,
                height: orientation == .v ? weight - gap : height,
                virtual: Rect(
                    topLeftX: virtualPoint.x,
                    topLeftY: virtualPoint.y,
                    width: orientation == .h ? weight : virtual.width,
                    height: orientation == .v ? weight : virtual.height,
                ),
                params,
                &frames,
            )
            virtualPoint = virtualPoint.addingOffset(orientation, weight)
            point = point.addingOffset(orientation, weight)
        }
    }

    fileprivate func layoutAccordion(
        _ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ params: LayoutParams, _ frames: inout [WindowFrame],
    ) {
        guard let mruIndex = mostRecentChild?.tilingSlot?.index else { return }
        let padding = params.accordionPadding
        for (index, child) in children.enumerated() {
            let (lPadding, rPadding): (CGFloat, CGFloat) = switch index {
                case 0 where children.count == 1: (0, 0)
                case 0:                           (0, padding)
                case children.indices.last:       (padding, 0)
                case mruIndex - 1:                (0, 2 * padding)
                case mruIndex + 1:                (2 * padding, 0)
                default:                          (padding, padding)
            }
            child.layoutTiling(
                point.addingOffset(orientation, lPadding),
                width: orientation == .h ? width - rPadding - lPadding : width,
                height: orientation == .v ? height - lPadding - rPadding : height,
                virtual: virtual,
                params,
                &frames,
            )
        }
    }
}
