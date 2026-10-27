import AppKit
import Common

/// Use it instead of NSScreen because it can be mocked in tests
struct MonitorInfo {
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
    func approximation(_ point: CGPoint) -> MonitorInfo {
        all[index { point.distance(toOuterFrame: $0.rect) }]
    }

    func hideCorner(of monitor: MonitorInfo) -> OptimalHideCorner { hideCorners[index(of: monitor)] }

    /// The first index with the smallest distance
    private func index(minimizing distance: (MonitorInfo) -> CGFloat) -> Int {
        (1 ..< all.count).reduce(0) { best, index in distance(all[index]) < distance(all[best]) ? index : best }
    }

    func hasSameCorners(as other: Monitors) -> Bool {
        all.map(\.rect.topLeftCorner) == other.all.map(\.rect.topLeftCorner)
    }
}

enum OptimalHideCorner {
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

/// The monitors as macOS reports them now. Empty while there are no screens (e.g., during display reconfiguration).
/// Tests set the snapshot with ``updateMonitors(_:)``, and this returns it
func liveMonitorInfos() -> [MonitorInfo] {
    if isUnitTest { return world.monitors.hasScreens ? Array(world.monitors.all) : [] }
    let screens = NSScreen.screens
    guard let mainScreen = screens.singleOrNil(where: \.isMainScreen) ?? screens.first else { return [] }
    let mainMonitorHeight = mainScreen.frame.height
    return screens.enumerated().map {
        $0.element.toMonitorInfo(
            monitorAppKitNsScreenScreensId: $0.offset + 1,
            mainMonitorHeight: mainMonitorHeight,
            isMain: $0.element.isMainScreen,
        )
    }
}

/// Same as `!liveMonitorInfos().isEmpty`, but cheap (`liveMonitorInfos` reads `NSScreen.visibleFrame`, which is slow). For
/// the re-checks after the awaits of a session: the screens can disappear while it runs, its snapshot doesn't show that
func liveHasScreens() -> Bool {
    isUnitTest ? world.monitors.hasScreens : !NSScreen.screens.isEmpty
}

// Note to myself: Don't use NSScreen.main, it's garbage
// 1. The name is misleading, it's supposed to be called "focusedScreen"
// 2. It's inaccurate because NSScreen.main doesn't work correctly from NSWorkspace.didActivateApplicationNotification &
//    kAXFocusedWindowChangedNotification callbacks.
extension NSScreen {
    /// ``frame`` and ``visibleFrame`` are crazy: (0, 0) is the main screen's bottom left corner, and the positive
    /// y-axis goes up. ``MonitorInfo`` normalizes them to the coordinates of ``MacWindow.topLeftCorner``: (0, 0) is the
    /// main screen's top left corner, and the positive y-axis goes down
    fileprivate func toMonitorInfo(monitorAppKitNsScreenScreensId: Int, mainMonitorHeight: CGFloat, isMain: Bool) -> MonitorInfo {
        MonitorInfo(
            monitorAppKitNsScreenScreensId: monitorAppKitNsScreenScreensId,
            name: localizedName,
            rect: frame.monitorFrameNormalized(mainMonitorHeight: mainMonitorHeight),
            visibleRect: visibleFrame.monitorFrameNormalized(mainMonitorHeight: mainMonitorHeight),
            isMain: isMain,
        )
    }

    fileprivate var isMainScreen: Bool {
        frame.minX == 0 && frame.minY == 0
    }
}
