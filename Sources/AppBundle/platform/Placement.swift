import AppKit

/// A write of a window's frame, see ``Platform/apply(_:)``
nonisolated enum Placement: Equatable, Sendable {
    /// nil keeps the position or the size
    case frame(WindowId, topLeft: CGPoint?, size: CGSize?)
    /// Hides the window in a corner of its monitor, see ``ParkTarget``
    case park(WindowId, ParkTarget)
}

/// Where ``Placement/park(_:_:)`` hides a window: it keeps one pixel on the monitor, so that macOS doesn't move it back
nonisolated struct ParkTarget: Equatable, Sendable {
    let corner: OptimalHideCorner
    /// The visible rect of the window's monitor
    let visibleRect: Rect
}
