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

private let testMonitorInfoRect = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
private let testMonitorInfo = MonitorInfo(
    monitorAppKitNsScreenScreensId: 1,
    name: "Test Monitor",
    rect: testMonitorInfoRect,
    visibleRect: testMonitorInfoRect,
    isMain: true,
)

// Fallback: If main screen can't be found (e.g., during display reconfiguration), return screens.first
private func mainScreen(_ screens: [NSScreen]) -> (index: Int, value: NSScreen)? {
    screens.withIndex.singleOrNil(where: \.value.isMainScreen) ?? screens.first.map { (index: 0, value: $0) }
}

var mainMonitorInfo: MonitorInfo {
    if isUnitTest { return testMonitorInfo }
    // Return testMonitor if there are no screens (e.g., during display reconfiguration) to avoid crash
    guard let screen = mainScreen(NSScreen.screens) else { return testMonitorInfo }
    return screen.value.toMonitorInfo(
        monitorAppKitNsScreenScreensId: screen.index + 1,
        mainMonitorHeight: screen.value.frame.height,
        isMain: true, // Even if it's the screens.first fallback
    )
}

/// Test-only: `true` simulates the absence of screens (`NSScreen.screens` is briefly empty during display reconfiguration)
@TaskLocal var noScreensForTests = false

/// Same as `!monitorInfos.isEmpty`, but cheap (`monitorInfos` reads `NSScreen.visibleFrame`, which is slow)
var hasScreens: Bool { isUnitTest ? !noScreensForTests : !NSScreen.screens.isEmpty }

var monitorInfos: [MonitorInfo] {
    if isUnitTest { return noScreensForTests ? [] : [testMonitorInfo] }
    let screens = NSScreen.screens
    guard let main = mainScreen(screens) else { return [] }
    let mainMonitorHeight = main.value.frame.height
    return screens.enumerated().map {
        $0.element.toMonitorInfo(
            monitorAppKitNsScreenScreensId: $0.offset + 1,
            mainMonitorHeight: mainMonitorHeight,
            isMain: $0.element.isMainScreen,
        )
    }
}

var sortedMonitorInfos: [MonitorInfo] {
    monitorInfos.sortedBy([\.rect.minX, \.rect.minY])
}
