import AppKit
import Common

/// The placement batch of P4. Its order is the contract: the unparks of the popups, the visible workspaces' placements,
/// then a park per window of the invisible workspaces (to reduce flicker), then the parks of their popups (see
/// ``popupPlacements(_:_:)``). While AeroSpace is disabled, every workspace's placements: every window unparks. A floating
/// child window parks before its parent and unparks after it (see ``floatingChildDepths(_:_:)``)
func placements() -> [Placement] {
    // No screens (e.g., the screens disappeared in the middle of the refresh session): wait for them. Don't hide windows in
    // the corners of a monitor that doesn't exist. AeroSpace can't be disabled while there are no screens (EnableCommand),
    // so the windows were unhidden when it was disabled, unless the screens vanished during that session. Then the next
    // `enable off` with screens unhides them
    if !world.platform.hasScreens { return [] }
    let popups = macosPopupWindowsContainer.children.filterIsInstance(of: Window.self)
    let floating = Workspace.all.flatMap(\.floatingWindows)
    let ids = (popups + floating).map(\.windowId)
    let parents = ids.isEmpty ? [:] : world.platform.windowServerParents(ids)
    let childDepths = floatingChildDepths(floating, parents)
    let popupPlacements = popupPlacements(popups, parents)
    var shown: [Placement] = []
    var parks: [Placement] = []
    if !world.isEnabled {
        for workspace in Workspace.all {
            shown += workspace.layoutPlacements() // Unparks every window
        }
    } else {
        let monitors = world.monitors
        for monitor in monitors.all {
            shown += monitor.activeWorkspace.layoutPlacements()
        }
        for workspace in Workspace.all where !workspace.isVisible {
            let monitor = workspace.workspaceMonitor
            let corner = monitors.hideCorner(of: monitor)
            for window in workspace.allLeafWindowsRecursive {
                let isZoom = window.app.knownBundleId == .zoom
                let target = ParkTarget(
                    corner: corner, monitor: monitor, monitors: monitors.all, isFloating: window.isFloating, isZoom: isZoom,
                    followsParent: childDepths[window.windowId] != nil,
                )
                parks.append(.park(window.windowId, target))
            }
        }
    }
    return popupPlacements.unparks + shown.sorted(byDepth: childDepths, deepestFirst: false)
        + parks.sorted(byDepth: childDepths, deepestFirst: true) + popupPlacements.parks
}

/// The floating windows whose window server owner (see ``windowServerOwner(of:_:)``) is a window of the same workspace
/// (e.g. an AppKit child window, a wxWidgets dialog), with their depth: 1 for a child of a window that isn't such a child,
/// 2 for a child of that child, and so on. macOS moves a child window along with its parent, and AppKit keeps a titled
/// one 40 points on screen: after its parent's park, it shows at the screen's edge. So a child parks before its parent,
/// while it's still where the user put it, and it remembers that position as is (``ParkTarget/followsParent``). Parked
/// after its parent, it would remember the edge, and its unpark would put it there. It unparks after its parent, which
/// takes it along: its unpark puts it back where it was
private func floatingChildDepths(_ floating: [Window], _ parents: [WindowId: WindowId]) -> [WindowId: Int] {
    var owners: [WindowId: WindowId] = [:]
    for window in floating {
        guard let owner = windowServerOwner(of: window.windowId, parents), owner != window,
              let workspace = owner.workspacePlacement?.workspace, workspace == window.workspacePlacement?.workspace
        else { continue }
        owners[window.windowId] = owner.windowId
    }
    var depths: [WindowId: Int] = [:]
    for id in owners.keys {
        var depth = 0
        var current = id
        while let owner = owners[current], depth < 8 { // The bound guards against a cycle
            depth += 1
            current = owner
        }
        depths[id] = depth
    }
    return depths
}

extension [Placement] {
    /// Stable, by the depth of the window in `childDepths` (0 if it isn't there)
    fileprivate func sorted(byDepth childDepths: [WindowId: Int], deepestFirst: Bool) -> [Placement] {
        if childDepths.isEmpty { return self }
        func key(_ item: (offset: Int, element: Placement)) -> (Int, Int) {
            let depth = childDepths[item.element.windowId] ?? 0
            return (deepestFirst ? -depth : depth, item.offset)
        }
        return enumerated().sorted { key($0) < key($1) }.map(\.element)
    }
}

/// The popups follow the workspace of their window server parent (an AppKit child window, a sheet, a Chromium bubble): a
/// popup of a window of an invisible workspace parks, see ``ParkTarget/followsParent``, and it unparks when the workspace
/// shows. The unparks come first: the parents' unparks take the popups along. The parks come last: a child window that
/// its parent's park took off-screen stays there. A popup whose parent is a popup follows that one's parent. A popup
/// without such a parent (e.g. a picture in picture window, a menu bar app's popover), a popup of a hidden app's window
/// (macOS hides them) and 1Password's popups (its mini window shows on every workspace) stay where they are
private func popupPlacements(_ popups: [Window], _ parents: [WindowId: WindowId]) -> (unparks: [Placement], parks: [Placement]) {
    let monitors = world.monitors
    var unparks: [Placement] = []
    var parks: [Placement] = []
    for popup in popups where popup.app.knownBundleId != ._1password {
        guard let (workspace, placement) = windowServerOwner(of: popup.windowId, parents)?.workspacePlacement else { continue }
        if case .macosHiddenApp = placement { continue }
        if !world.isEnabled || workspace.isVisible {
            unparks.append(.unparkPopup(popup.windowId))
        } else {
            let monitor = workspace.workspaceMonitor
            let target = ParkTarget(
                corner: monitors.hideCorner(of: monitor), monitor: monitor, monitors: monitors.all, isFloating: false, isZoom: false,
                followsParent: true,
            )
            parks.append(.park(popup.windowId, target))
        }
    }
    return (unparks, parks)
}

extension Workspace {
    /// The placements of the workspace's windows: the frames of ``layoutTiling()`` in their order, then the floating
    /// windows, which keep their frame unless they are off the workspace's monitor, then the macOS fullscreen windows,
    /// which stay where they are. A hidden app's windows get none: they stay parked, so that a floating one goes back
    /// where it was once the app is unhidden. Nor does the floating window that the user drags: the mouse places it
    func layoutPlacements() -> [Placement] {
        if isEffectivelyEmpty { return [] }
        var placements = layoutTiling()
        let floatingTarget = FloatingTarget(monitor: workspaceMonitor, monitors: world.monitors.all, isShown: isVisible)
        for window in floatingWindows where window.windowId != world.draggedFloatingWindow?.id {
            window.lastAppliedLayoutPhysicalRect = nil
            window.lastAppliedLayoutVirtualRect = nil
            if window.isFullscreen {
                placements.append(window.fullscreenFrame(on: workspaceMonitor))
                window.isFullscreen = false
            } else {
                placements.append(.floating(window.windowId, floatingTarget))
            }
        }
        for case let window as Window in existingContainer(.macosFullscreen)?.children ?? [] {
            placements.append(.leave(window.windowId))
        }
        return placements
    }

    /// Lays out the tiling tree without AX calls: writes the layout rects and the tiles weights into the tree and returns
    /// a ``Placement/frame(_:topLeft:size:)`` per tiling window, depth first. Without a root container there are none
    func layoutTiling() -> [Placement] {
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
        var frames: [Placement] = []
        root.layoutTiling(rect.topLeftCorner, width: rect.width, height: height, virtual: rect, params, &frames)
        return frames
    }
}

/// What the tiling layout reads besides the tree. Read once per workspace
private struct LayoutParams {
    let monitor: MonitorInfo
    let gaps: ResolvedGaps
    let accordionPadding: CGFloat
    /// The window that is moved or resized with the mouse. Its frame is left alone
    let skippedWindowId: WindowId?
    /// The root's most recent window: the only one that a `fullscreen` window fills the monitor with
    let fullscreenCandidate: Window?
}

extension TreeNode {
    fileprivate func layoutTiling(
        _ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ params: LayoutParams, _ frames: inout [Placement],
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
                    let rect = window.app.knownBundleId == .cmux
                        ? physicalRect.notLookingZoomed(in: params.monitor.visibleRect)
                        : physicalRect
                    lastAppliedLayoutPhysicalRect = rect
                    window.isFullscreen = false
                    frames.append(.frame(window.windowId, topLeft: rect.topLeftCorner, size: rect.size))
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
    fileprivate func fullscreenFrame(on monitor: MonitorInfo) -> Placement {
        let rect = noOuterGapsInFullscreen ? monitor.visibleRect : monitor.visibleRectPaddedByOuterGaps
        return .frame(windowId, topLeft: rect.topLeftCorner, size: rect.size)
    }
}

extension TilingContainer {
    fileprivate func layoutTiles(
        _ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ params: LayoutParams, _ frames: inout [Placement],
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
        _ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ params: LayoutParams, _ frames: inout [Placement],
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
