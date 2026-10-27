import AppKit
import Common

/// The CoreGraphics id of a window: the key of ``World/windows``. The CLI and the JSON output show the raw number
nonisolated struct WindowId: Hashable, Comparable, Sendable, CustomStringConvertible {
    let raw: CGWindowID

    static func < (lhs: WindowId, rhs: WindowId) -> Bool { lhs.raw < rhs.raw }
    var description: String { raw.description }
}
