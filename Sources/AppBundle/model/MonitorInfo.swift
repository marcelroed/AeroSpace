import AppKit
import Common

private struct MonitorInfoImpl {
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let rect: Rect
    let visibleRect: Rect
    let isMain: Bool
}

extension MonitorInfoImpl: MonitorInfo {
    var height: CGFloat { rect.height }
    var width: CGFloat { rect.width }
}

/// Use it instead of NSScreen because it can be mocked in tests
protocol MonitorInfo: AeroAny {
    /// The index in NSScreen.screens array. 1-based index
    var monitorAppKitNsScreenScreensId: Int { get }
    var name: String { get }
    var rect: Rect { get }
    var visibleRect: Rect { get }
    var width: CGFloat { get }
    var height: CGFloat { get }
    var isMain: Bool { get }
}

// Note to myself: Don't use NSScreen.main, it's garbage
// 1. The name is misleading, it's supposed to be called "focusedScreen"
// 2. It's inaccurate because NSScreen.main doesn't work correctly from NSWorkspace.didActivateApplicationNotification &
//    kAXFocusedWindowChangedNotification callbacks.
extension NSScreen {
    fileprivate func toMonitorInfo(monitorAppKitNsScreenScreensId: Int, mainMonitorHeight: CGFloat, isMain: Bool) -> MonitorInfo {
        MonitorInfoImpl(
            monitorAppKitNsScreenScreensId: monitorAppKitNsScreenScreensId,
            name: localizedName,
            rect: rect(mainMonitorHeight: mainMonitorHeight),
            visibleRect: visibleRect(mainMonitorHeight: mainMonitorHeight),
            isMain: isMain,
        )
    }

    fileprivate var isMainScreen: Bool {
        frame.minX == 0 && frame.minY == 0
    }

    /// The function is a replacement for Apple's crazy ``frame``
    ///
    /// - For ``MacWindow.topLeftCorner``, (0, 0) is main screen top left corner, and positive y-axis goes down.
    /// - For ``frame``, (0, 0) is main screen bottom left corner, and positive y-axis goes up (which is crazy).
    ///
    /// The function "normalizes" ``frame``
    fileprivate func rect(mainMonitorHeight: CGFloat) -> Rect { frame.monitorFrameNormalized(mainMonitorHeight: mainMonitorHeight) }

    /// Same as ``rect(mainMonitorHeight:)`` but for ``visibleFrame``
    fileprivate func visibleRect(mainMonitorHeight: CGFloat) -> Rect { visibleFrame.monitorFrameNormalized(mainMonitorHeight: mainMonitorHeight) }
}

private let testMonitorInfoRect = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
private let testMonitorInfo = MonitorInfoImpl(
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

var monitorInfos: [MonitorInfo] {
    if isUnitTest { return [testMonitorInfo] }
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
