import AppKit
import Common

/// Use it instead of NSScreen because it can be mocked in tests
nonisolated struct MonitorInfo: Equatable, Sendable {
    /// The index in NSScreen.screens array. 1-based index
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let rect: Rect
    let visibleRect: Rect
    let isMain: Bool

    var width: CGFloat { rect.width }
    var height: CGFloat { rect.height }
    /// The orientation of the longer side
    var orientation: Orientation { width >= height ? .h : .v }
}

/// The monitors of a session: ``updateMonitors(_:)`` replaces the snapshot in ``World/monitors`` at the start of every
/// session, so all the code of a session sees the same monitors
struct Monitors {
    /// Sorted by the top-left corner: left to right, then top to bottom. The order of the monitor ids and of
    /// `focus-monitor next`
    let all: NonEmptyArray<MonitorInfo>
    let main: MonitorInfo
    /// false while macOS reports no screens (e.g., during display reconfiguration). `all` keeps the last monitors meanwhile
    private(set) var hasScreens: Bool = true
    /// The corner of each monitor of `all` where the windows of the invisible workspaces hide
    private let hideCorners: [OptimalHideCorner]

    /// nil if there are no monitors
    init?(_ monitors: [MonitorInfo]) {
        guard let first = monitors.first, let all = NonEmptyArray(monitors.sortedBy([\.rect.minX, \.rect.minY])) else { return nil }
        self.all = all
        // Fallback: if the main monitor can't be found (e.g., during display reconfiguration), the first in macOS's order
        main = monitors.singleOrNil(where: \.isMain) ?? first
        hideCorners = all.map { optimalHideCorner(of: $0, among: all) }
    }

    /// Before the first ``updateMonitors(_:)`` of the startup, which runs before anything can start a session or read the
    /// focus. If the screens vanish right before it, the first workspace waits on this monitor until they come back
    static let beforeFirstSnapshot: Monitors = {
        let rect = Rect(topLeftX: 0, topLeftY: 0, width: 0, height: 0)
        let monitor = MonitorInfo(monitorAppKitNsScreenScreensId: 1, name: "", rect: rect, visibleRect: rect, isMain: true)
        return Monitors([monitor]).orDie().withoutScreens
    }()

    /// The same monitors, while there are no screens
    var withoutScreens: Monitors {
        var result = self
        result.hasScreens = false
        return result
    }

    /// The index in `all` of `monitor`, or of the monitor whose top-left corner is the closest to `monitor`'s if `monitor` is
    /// from an older snapshot (e.g. held across an await while the monitors changed). A scan: there are a few monitors
    func index(of monitor: MonitorInfo) -> Int {
        let corner = monitor.rect.topLeftCorner
        return index { ($0.rect.topLeftCorner - corner).vectorLength }
    }

    /// The monitor that contains `point`, or the closest one
    func approximation(_ point: CGPoint) -> MonitorInfo { nearestMonitor(to: point, in: all) }

    func hideCorner(of monitor: MonitorInfo) -> OptimalHideCorner { hideCorners[index(of: monitor)] }

    /// The first index with the smallest distance
    private func index(minimizing distance: (MonitorInfo) -> CGFloat) -> Int {
        (1 ..< all.count).reduce(0) { best, index in distance(all[index]) < distance(all[best]) ? index : best }
    }

    func hasSameCorners(as other: Monitors) -> Bool {
        all.map(\.rect.topLeftCorner) == other.all.map(\.rect.topLeftCorner)
    }
}

nonisolated enum OptimalHideCorner: Equatable, Sendable {
    case bottomLeftCorner, bottomRightCorner
}

/// The bottom corner of `monitor` that the other monitors cover the least: a window hidden there peeks out the least
private func optimalHideCorner(of monitor: MonitorInfo, among monitors: NonEmptyArray<MonitorInfo>) -> OptimalHideCorner {
    let xOff = monitor.width * 0.1
    let yOff = monitor.height * 0.1
    // brc = bottomRightCorner
    let brc1 = monitor.rect.bottomRightCorner + CGPoint(x: 2, y: -yOff)
    let brc2 = monitor.rect.bottomRightCorner + CGPoint(x: -xOff, y: 2)
    let brc3 = monitor.rect.bottomRightCorner + CGPoint(x: 2, y: 2)

    // blc = bottomLeftCorner
    let blc1 = monitor.rect.bottomLeftCorner + CGPoint(x: -2, y: -yOff)
    let blc2 = monitor.rect.bottomLeftCorner + CGPoint(x: xOff, y: 2)
    let blc3 = monitor.rect.bottomLeftCorner + CGPoint(x: -2, y: 2)

    func contains(_ monitor: MonitorInfo, _ point: CGPoint) -> Int { monitor.rect.contains(point) ? 1 : 0 }
    let important = 10

    let leftScore = monitors.sum { contains($0, blc1) + contains($0, blc2) + important * contains($0, blc3) }
    let rightScore = monitors.sum { contains($0, brc1) + contains($0, brc2) + important * contains($0, brc3) }
    return leftScore < rightScore ? .bottomLeftCorner : .bottomRightCorner
}
