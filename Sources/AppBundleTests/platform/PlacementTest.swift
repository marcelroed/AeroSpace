@testable import AppBundle
import AppKit
import Common
import Testing

// The AX quirks of the placements, through FakePlatform: it runs AxApp's code (PlacementState) against its windows
@Suite(.aeroSpaceGlobalState)
struct PlacementTest {
    @Test
    func aParkedWindowKeepsOnePixelOnTheMonitorButZoomDoesNot() {
        let zoom = AppInfo(pid: 1, bundleId: KnownBundleId.zoom.rawValue, name: "zoom.us", execPath: nil, bundlePath: nil)
        fake.windows[1] = FakeWindow(app: testApp, rect: rect(100, 100, 400, 300), title: "1")
        fake.windows[2] = FakeWindow(app: zoom, rect: rect(100, 100, 400, 300), title: "2")
        let target = parkTarget(.bottomRightCorner, testMonitor)

        fake.apply([.park(1, target), .park(2, target)])

        expectEqual(fake.windows[1]?.rect?.topLeftCorner, CGPoint(x: 1919, y: 1079))
        expectEqual(fake.windows[2]?.rect?.topLeftCorner, CGPoint(x: 1920, y: 1080)) // #527
    }

    @Test
    func theBottomLeftCornerReadsTheSizeAgainWhenTheWindowParksAgain() {
        fake.windows[1] = FakeWindow(app: testApp, rect: rect(100, 100, 400, 300), title: "1")
        let target = parkTarget(.bottomLeftCorner, testMonitor)
        fake.apply([.park(1, target)])
        expectEqual(fake.windows[1]?.rect?.topLeftCorner, CGPoint(x: 1 - 400, y: 1079))

        fake.windows[1]?.rect = rect(1 - 400, 1079, 600, 300) // The app made the window wider
        fake.apply([.park(1, target)])

        expectEqual(fake.windows[1]?.rect?.topLeftCorner, CGPoint(x: 1 - 600, y: 1079))
    }

    /// The park remembers where the window was relative to the monitor it was on (#1492), and only once: the second park
    /// doesn't remember the corner (90a7c672). The unpark puts it at the same relative position on its workspace's monitor
    @Test
    func aParkRemembersThePositionOnceAndTheUnparkPutsItThereOnTheWorkspacesMonitor() {
        let monitors = NonEmptyArray(testMonitor, [rightTestMonitor])
        fake.windows[1] = FakeWindow(app: testApp, rect: rect(1920 + 192, 108, 400, 300), title: "1")
        let target = parkTarget(.bottomRightCorner, rightTestMonitor, monitors)
        fake.apply([.park(1, target)])
        fake.windows[1]?.rect = rect(3000, 900, 400, 300) // The app moved the parked window
        fake.apply([.park(1, target)])
        expectEqual(fake.windows[1]?.rect?.topLeftCorner, CGPoint(x: 3839, y: 1079))

        fake.apply([.floating(1, FloatingTarget(monitor: testMonitor, monitors: monitors, isShown: true))])

        expectEqual(fake.windows[1]?.rect?.topLeftCorner, CGPoint(x: 192, y: 108))
        #expect(!fake.isParked(1))
    }

    @Test
    func anUnparkedWindowFitsOnTheMonitorAtItsLastFloatingSize() {
        fake.windows[1] = FakeWindow(app: testApp, rect: rect(1728, 972, 400, 300), title: "1") // At 90 % of the monitor
        fake.apply([.park(1, parkTarget(.bottomRightCorner, testMonitor, isFloating: true))])

        fake.apply([.floating(1, FloatingTarget(monitor: testMonitor, monitors: NonEmptyArray(testMonitor), isShown: true))])

        expectEqual(fake.windows[1]?.rect?.topLeftCorner, CGPoint(x: 1920 - 400, y: 1080 - 300)) // #1519
    }

    @Test
    func aFloatingWindowOnAnotherMonitorMovesToTheSameRelativePositionOnItsWorkspacesMonitor() {
        let monitors = NonEmptyArray(testMonitor, [rightTestMonitor])
        fake.windows[1] = FakeWindow(app: testApp, rect: rect(1920 + 192, 108, 400, 300), title: "1")
        let target = FloatingTarget(monitor: testMonitor, monitors: monitors, isShown: true)

        fake.apply([.floating(1, target)])
        expectEqual(fake.windows[1]?.rect?.topLeftCorner, CGPoint(x: 192, y: 108))

        fake.resetCalls()
        fake.apply([.floating(1, target)])
        expectEqual(fake.calls(of: .frame), []) // On its workspace's monitor, the window stays
    }

    @Test
    func aWindowThatTheLayoutLeavesIsNoLongerParkedAndStaysWhereItIs() {
        fake.windows[1] = FakeWindow(app: testApp, rect: rect(100, 100, 400, 300), title: "1")
        fake.apply([.park(1, parkTarget(.bottomRightCorner, testMonitor))])
        fake.windows[1]?.rect = rect(0, 0, 1920, 1080) // macOS fullscreen

        fake.apply([.leave(1)])
        fake.apply([.floating(1, FloatingTarget(monitor: testMonitor, monitors: NonEmptyArray(testMonitor), isShown: true))])

        #expect(!fake.isParked(1))
        expectEqual(fake.windows[1]?.rect, rect(0, 0, 1920, 1080))
    }

    /// A placement made stale by a newer write of the window stops before its next AX call. An unpark that didn't write the
    /// position leaves the window parked, so the next placement unparks it. Termination stops them the same way (R-PLAT L4)
    @Test
    func aStalePlacementStopsBeforeItsNextAxCallAndAStaleUnparkKeepsTheWindowParked() {
        var state = PlacementState(lastFloatingSize: nil)
        let target = FloatingTarget(monitor: testMonitor, monitors: NonEmptyArray(testMonitor), isShown: true)
        state.apply(.park(1, parkTarget(.bottomRightCorner, testMonitor)), to: StaleAfter(calls: 100), isZoom: false)

        let stale = StaleAfter(calls: 0)
        state.apply(.park(1, parkTarget(.bottomRightCorner, testMonitor)), to: stale, isZoom: false)
        state.apply(.frame(1, topLeft: .zero, size: nil), to: stale, isZoom: false)
        state.apply(.floating(1, target), to: stale, isZoom: false)
        expectEqual(stale.log.items, [])

        let staleAtTheWrite = StaleAfter(calls: 1)
        state.apply(.floating(1, target), to: staleAtTheWrite, isZoom: false)
        expectEqual(staleAtTheWrite.log.items, [])
        #expect(state.isParked)

        let current = StaleAfter(calls: 100)
        state.apply(.floating(1, target), to: current, isZoom: false)
        #expect(!state.isParked)
        expectEqual(current.log.items.first, "setFrame")
    }

    private func parkTarget(
        _ corner: OptimalHideCorner,
        _ monitor: MonitorInfo,
        _ monitors: NonEmptyArray<MonitorInfo>? = nil,
        isFloating: Bool = false,
    ) -> ParkTarget {
        ParkTarget(corner: corner, monitor: monitor, monitors: monitors ?? NonEmptyArray(monitor), isFloating: isFloating)
    }
}

/// A window at (100, 100, 400, 300) that turns stale after `calls` calls of ``isCurrent()``. It logs its AX calls
private struct StaleAfter: @MainActor PlacementWindow {
    let calls: Int
    let log = CallLog()

    func isCurrent() -> Bool {
        log.isCurrentCalls += 1
        return log.isCurrentCalls <= calls
    }

    func topLeft() -> CGPoint? {
        log.append("topLeft")
        return CGPoint(x: 100, y: 100)
    }

    func size() -> CGSize? {
        log.append("size")
        return CGSize(width: 400, height: 300)
    }

    func setFrame(topLeft: CGPoint?, size: CGSize?) -> Bool {
        guard isCurrent() else { return false }
        log.append("setFrame")
        return topLeft != nil
    }
}

private final class CallLog {
    var isCurrentCalls = 0
    var items: [String] = []

    func append(_ item: String) { items.append(item) }
}
