import AppKit

/// Where a window goes, see ``Platform/apply(_:)``. The platform runs the placements of each app in the batch's order (the
/// shown workspaces' placements, then the parks, which also wait for the other apps' shown placements), latest wins per
/// window. AxApp and FakePlatform run them with the same
/// code: ``PlacementState``
nonisolated enum Placement: Equatable, Sendable {
    /// The layout's frame of a window. It's written only if the window isn't there already, see
    /// ``PlacementState/apply(_:to:)``
    case frame(WindowId, topLeft: CGPoint, size: CGSize)
    /// A floating window of a workspace: it unparks to where it was, then it stays where it is unless it's off the
    /// workspace's monitor, see ``floatingTopLeft(current:target:)``
    case floating(WindowId, FloatingTarget)
    /// Hides the window in a corner of its workspace's monitor, see ``ParkTarget``
    case park(WindowId, ParkTarget)
    /// A macOS fullscreen window of a shown workspace: it stays where it is, and it's no longer parked. A park of a
    /// fullscreen window remembered its fullscreen frame: an unpark after the fullscreen ends would move it to the top left
    /// corner of its monitor
    case leave(WindowId)

    var windowId: WindowId {
        switch self {
            case .frame(let id, _, _), .floating(let id, _), .park(let id, _), .leave(let id): id
        }
    }
}

/// Where a ``Placement/floating(_:_:)`` window belongs
nonisolated struct FloatingTarget: Equatable, Sendable {
    let monitor: MonitorInfo
    /// All the monitors, to find the one the window is on
    let monitors: NonEmptyArray<MonitorInfo>
    /// The workspace is shown on `monitor`, so a window on `monitor` stays. false only while AeroSpace is disabled, which
    /// lays out every workspace
    let isShown: Bool
}

/// Where a ``Placement/park(_:_:)`` window hides: it keeps one pixel on the monitor, so that macOS doesn't move it back
nonisolated struct ParkTarget: Equatable, Sendable {
    let corner: OptimalHideCorner
    /// The workspace's monitor: the window goes to the corner of its visible rect
    let monitor: MonitorInfo
    /// All the monitors, to find the one the window is on
    let monitors: NonEmptyArray<MonitorInfo>
    /// The park remembers a floating window's size, for its unpark and `layout floating`
    let isFloating: Bool
    /// A window of Zoom keeps no pixel on the monitor: Zoom would jump off with one (#527)
    let isZoom: Bool
}

/// A window as ``PlacementState`` sees it: an AX window of AxApp, or a window of FakePlatform
nonisolated protocol PlacementWindow {
    /// false once a newer write of the window was posted or termination started: stop before the next AX call
    func isCurrent() -> Bool
    /// The position and the size, in one AX call. nil unless AX tells both
    func rect() -> Rect?
    /// Writes the size, then the position, then the size again (#143, #335), and stops once it's not current. true if it
    /// wrote the position
    @discardableResult
    func setFrame(topLeft: CGPoint?, size: CGSize?) -> Bool
}

/// The state of a window's placements, which AxApp keeps per window on the app's thread (FakePlatform keeps the same). A
/// placement checks the state, reads the window, updates the state and writes the window in one job, so that no other
/// placement of the window runs in between (the 90a7c672 race of a park's read is gone)
nonisolated struct PlacementState {
    /// Set while the window is parked: where it was, relative to the monitor it was on
    private var parkedAt: CGPoint? = nil
    /// The size that termination and `layout floating` restore: the window's size when it was registered, then whenever
    /// a floating window parks or the size is remembered (`layout tiling`, `enable on`)
    private(set) var lastFloatingSize: CGSize?
    /// Where the window was last seen: what the platform's last read of its rect found (``recordRead(_:)``), or the
    /// frame that the last `.frame` placement found it at or wrote
    private var lastFrame: Rect? = nil

    init(lastFloatingSize: CGSize?) {
        self.lastFloatingSize = lastFloatingSize
    }

    var isParked: Bool { parkedAt != nil }

    /// A read of the window's rect outside the placements (e.g., the drag of a tile) found it at `rect`. nil: unknown
    mutating func recordRead(_ rect: Rect?) { lastFrame = rect }

    mutating func apply(_ placement: Placement, to window: some PlacementWindow) {
        guard window.isCurrent() else { return } // Before any AX call: termination waits for this job
        switch placement {
            case .frame(_, let topLeft, let size):
                // It writes only a window that isn't there: each write makes the app lay out the window again. It reads
                // first, unless the window is known to be elsewhere: parked, or last seen at another frame. A skipped read
                // always becomes a write, because `lastFrame` may be stale: the app or the user may have moved the window
                let frame = Rect(topLeftX: topLeft.x, topLeftY: topLeft.y, width: size.width, height: size.height)
                let isKnownElsewhere = parkedAt != nil || lastFrame.map { !$0.isAt(frame) } == true
                let isThere = !isKnownElsewhere && window.rect().map { $0.isAt(frame) } == true
                if isThere || window.setFrame(topLeft: topLeft, size: size) {
                    parkedAt = nil
                    lastFrame = frame
                }
            case .floating(_, let target):
                if let parkedAt {
                    let topLeft = unparkTopLeft(proportional: parkedAt, monitorRect: target.monitor.rect, lastFloatingSize: lastFloatingSize)
                    // Unparked once it's written. A stale unpark leaves the window parked for the next one
                    guard window.setFrame(topLeft: topLeft, size: nil) else { return }
                    self.parkedAt = nil
                }
                guard window.isCurrent(), let rect = window.rect(),
                      let topLeft = floatingTopLeft(current: rect, target: target),
                      topLeft != rect.topLeftCorner
                else { return }
                window.setFrame(topLeft: topLeft, size: nil)
            case .park(_, let target):
                if parkedAt == nil {
                    guard let rect = window.rect() else { return }
                    // Remember the position only once: a repeated park would remember the corner (90a7c672)
                    parkedAt = proportionalPosition(of: rect, monitors: target.monitors)
                    if target.isFloating {
                        lastFloatingSize = rect.size
                    }
                    // A park that turns stale before this write (e.g., while AxApp waits for the shown jobs) leaves the
                    // window in place but marked parked: the next placement writes it (`.floating` to where it is) or parks it
                    window.setFrame(topLeft: parkTopLeft(size: rect.size, target: target), size: nil)
                } else {
                    // Parked already: the window moves only if it isn't in the corner (e.g., the app moved it). The bottom
                    // left corner uses the size read now: the app may have resized the window
                    let rect = window.rect()
                    let topLeft = parkTopLeft(size: rect?.size, target: target)
                    if rect?.topLeftCorner != topLeft {
                        window.setFrame(topLeft: topLeft, size: nil)
                    }
                }
            case .leave:
                parkedAt = nil
        }
    }

    /// `layout tiling` and `enable on`: the size of the window now is its floating size
    mutating func rememberFloatingSize(of window: some PlacementWindow) {
        guard window.isCurrent(), let rect = window.rect() else { return }
        lastFloatingSize = rect.size
    }

    /// `layout floating`
    func restoreFloatingSize(to window: some PlacementWindow) {
        guard let lastFloatingSize else { return }
        window.setFrame(topLeft: nil, size: lastFloatingSize)
    }
}

nonisolated extension Rect {
    /// Within a point of the frame: AX gives whole points, and the layout's frames have fractions
    fileprivate func isAt(_ frame: Rect) -> Bool {
        let differences: [CGFloat] = [topLeftX - frame.topLeftX, topLeftY - frame.topLeftY, width - frame.width, height - frame.height]
        return differences.allSatisfy { abs($0) < 1 }
    }
}

/// The monitor that contains `point`, or the closest one: the first one with the smallest distance
nonisolated func nearestMonitor(to point: CGPoint, in monitors: NonEmptyArray<MonitorInfo>) -> MonitorInfo {
    monitors.rest.reduce(monitors.first) { nearest, monitor in
        point.distance(toOuterFrame: monitor.rect) < point.distance(toOuterFrame: nearest.rect) ? monitor : nearest
    }
}

/// Where a parked window goes: one pixel inside the bottom corner of its monitor's visible rect. The bottom left corner
/// needs the window's width: without it, the window goes to the bottom right corner
nonisolated func parkTopLeft(size: CGSize?, target: ParkTarget) -> CGPoint {
    // todo this ad hoc won't be necessary once I implement optimization suggested by Zalim
    let offset: CGFloat = target.isZoom ? 0 : 1
    let rect = target.monitor.visibleRect
    if target.corner == .bottomLeftCorner, let size {
        return CGPoint(x: rect.minX + offset - size.width, y: rect.maxY - offset)
    }
    return CGPoint(x: rect.maxX - offset, y: rect.maxY - offset)
}

/// Where the window is, relative to the rect of the monitor it's on now (#1492): (0, 0) is the monitor's top left corner,
/// (1, 1) its bottom right corner
nonisolated func proportionalPosition(of rect: Rect, monitors: NonEmptyArray<MonitorInfo>) -> CGPoint {
    let monitorRect = nearestMonitor(to: rect.center, in: monitors).rect
    let offset = rect.topLeftCorner - monitorRect.topLeftCorner
    return CGPoint(x: offset.x / monitorRect.width, y: offset.y / monitorRect.height)
}

/// Where an unparked window goes: its proportional position in `monitorRect`, moved left and up to fit at its last
/// floating size
nonisolated func unparkTopLeft(proportional: CGPoint, monitorRect: Rect, lastFloatingSize: CGSize?) -> CGPoint {
    let x = monitorRect.topLeftX + monitorRect.width * proportional.x
    let y = monitorRect.topLeftY + monitorRect.height * proportional.y
    // todo we probably should replace lastFloatingSize with proper floating window sizing
    // https://github.com/nikitabobko/AeroSpace/issues/1519
    let width = lastFloatingSize?.width ?? 0
    let height = lastFloatingSize?.height ?? 0
    return CGPoint(
        x: x.coerce(in: monitorRect.minX ... max(monitorRect.minX, monitorRect.maxX - width)),
        y: y.coerce(in: monitorRect.minY ... max(monitorRect.minY, monitorRect.maxY - height)),
    )
}

/// Where a floating window at `current` moves, nil if it stays. It stays on its workspace's monitor while the workspace is
/// shown there. Otherwise, it moves from the monitor it's on to the same relative position on the workspace's monitor
/// (visible rects), clamped to fit
nonisolated func floatingTopLeft(current: Rect, target: FloatingTarget) -> CGPoint? {
    let currentMonitor = nearestMonitor(to: current.center, in: target.monitors)
    if target.isShown && currentMonitor == target.monitor { return nil }
    let currentRect = currentMonitor.visibleRect
    let targetRect = target.monitor.visibleRect
    let x = targetRect.topLeftX + (current.topLeftX - currentRect.topLeftX) / currentRect.width * targetRect.width
    let y = targetRect.topLeftY + (current.topLeftY - currentRect.topLeftY) / currentRect.height * targetRect.height
    return CGPoint(
        x: x.coerce(in: targetRect.minX ... max(targetRect.minX, targetRect.maxX - current.width)),
        y: y.coerce(in: targetRect.minY ... max(targetRect.minY, targetRect.maxY - current.height)),
    )
}
