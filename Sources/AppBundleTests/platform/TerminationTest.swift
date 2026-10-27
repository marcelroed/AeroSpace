@testable import AppBundle
import AppKit
import Testing

@Suite
struct TerminationTest {
    /// Both termination paths restore onto the monitors' visible rects (below the menu bar, above the Dock)
    @Test
    func aWindowIsRestoredCenteredOnTheVisibleRectOfItsMonitor() {
        let main = MonitorInfo(
            monitorAppKitNsScreenScreensId: 1, name: "Main", rect: rect(0, 0, 1920, 1080), visibleRect: rect(0, 30, 1920, 1000), isMain: true,
        )
        let right = MonitorInfo(
            monitorAppKitNsScreenScreensId: 2, name: "Right", rect: rect(1920, 0, 1920, 1080), visibleRect: rect(1920, 0, 1920, 1080), isMain: false,
        )
        let monitors = TerminationMonitors(all: NonEmptyArray(main, [right]), main: main)

        let onRight = monitors.restoreFrame(windowRect: rect(3000, 500, 100, 100), CGSize(width: 800, height: 600))
        expectEqual(onRight.topLeft, CGPoint(x: 1920 + 560, y: 240))
        expectEqual(onRight.size, CGSize(width: 800, height: 600))

        let unknown = monitors.restoreFrame(windowRect: nil, nil)
        expectEqual(unknown.topLeft, CGPoint(x: 0, y: 30))
        expectEqual(unknown.size, CGSize(width: 1920, height: 1000))
    }
}
