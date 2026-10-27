@testable import AppBundle
import AppKit
import Common
import Testing

// The AX quirks of the placements, through FakePlatform: it runs AxApp's code (PlacementState) against its windows
@Suite(.aeroSpaceGlobalState)
struct PlacementTest {
    @Test
    func aParkedWindowKeepsOnePixelOnTheMonitorButZoomDoesNot() {
        let workspace = setUpTree("h_tiles(1)", workspace: "a") // Not shown: its windows park
        let zoom = AppInfo(pid: 1, bundleId: KnownBundleId.zoom.rawValue, name: "zoom.us", execPath: nil, bundlePath: nil)
        fake.windows[2] = FakeWindow(app: zoom, rect: rect(100, 100, 400, 300), title: "2")
        _ = Window(id: 2, zoom, parent: workspace.existingRootTilingContainer.orDie(), weight: 1, index: nil)
        testWindow(1).rect = rect(100, 100, 400, 300)

        fake.apply(placements())

        expectEqual(testWindow(1).rect?.topLeftCorner, CGPoint(x: 1919, y: 1079))
        expectEqual(testWindow(2).rect?.topLeftCorner, CGPoint(x: 1920, y: 1080)) // #527
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

    /// A parked window is in its corner when its x is. macOS clamps the y of some apps' parked windows (Helium), and the
    /// next layouts must not write them again
    @Test
    func aParkedWindowIsInItsCornerWhenItsXIs() {
        let target = parkTarget(.bottomRightCorner, testMonitor)
        let rows: [(name: String, afterThePark: Rect, isWritten: Bool)] = [
            ("y clamped by macOS", rect(1919, 1046, 400, 300), false),
            ("x moved by the app", rect(1880, 1079, 400, 300), true),
        ]
        for row in rows {
            fake.windows[1] = FakeWindow(app: testApp, rect: rect(100, 100, 400, 300), title: "1")
            fake.apply([.park(1, target)])
            fake.windows[1]?.rect = row.afterThePark
            fake.resetCalls()

            fake.apply([.park(1, target)])

            let writes: [PlatformCall] = row.isWritten ? [.frame(1, topLeft: CGPoint(x: 1919, y: 1079), size: nil)] : []
            expectEqual(fake.calls, [.park(1, target), .axRead(1)] + writes, "\(row.name)")
        }
    }

    /// A park records the x it wrote: AxApp's shown job waits until the window server shows the unparked window away from
    /// it. An unpark or a `.leave` clears it. A park that turned stale before its write records none: nothing waits then
    @Test
    func aParkRecordsTheXItWroteUntilTheWindowIsUnparkedOrLeft() {
        let park: Placement = .park(1, parkTarget(.bottomRightCorner, testMonitor))
        let floating = FloatingTarget(monitor: testMonitor, monitors: NonEmptyArray(testMonitor), isShown: true)
        let rows: [(name: String, next: Placement)] = [
            ("unparked as a tile", .frame(1, topLeft: .zero, size: CGSize(width: 400, height: 300))),
            ("unparked as a floating window", .floating(1, floating)),
            ("left as a macOS fullscreen window", .leave(1)),
        ]
        let cornerX: CGFloat? = 1919
        for row in rows {
            fake.windows[1] = FakeWindow(app: testApp, rect: rect(100, 100, 400, 300), title: "1")
            fake.apply([park])
            expectEqual(fake.windows[1]?.placement.cornerX, cornerX, "\(row.name)")
            fake.apply([row.next])
            expectEqual(fake.windows[1]?.placement.cornerX, nil, "\(row.name)")
        }

        var state = PlacementState(lastFloatingSize: nil)
        state.apply(park, to: StaleAfter(calls: 1), trustsLastSeen: false) // Stale at its write
        #expect(state.isParked)
        expectEqual(state.cornerX, nil)
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

    /// A hidden app's window parked with its workspace stays parked while the workspace is shown, so that it goes back
    /// where it was once the app is unhidden
    @Test
    func aHiddenAppsWindowGoesBackWhereItWasOnceTheAppIsUnhidden() {
        let workspace = setUpTree("h_tiles() floating(1)", workspace: "a")
        testWindow(1).rect = rect(100, 100, 400, 300)
        #expect(Workspace.get(byName: "b").focusWorkspace())
        world.platform.apply(placements())
        testWindow(1).move(to: workspace.containerCreatingIfNeeded(.macosHiddenApp)) // cmd-h

        #expect(workspace.focusWorkspace())
        world.platform.apply(placements())
        #expect(fake.isParked(1))

        testWindow(1).move(to: workspace.containerCreatingIfNeeded(.floating)) // Unhidden
        world.platform.apply(placements())
        expectEqual(testWindow(1).rect, rect(100, 100, 400, 300))
    }

    /// A macOS fullscreen window parked with its workspace: the park remembered its fullscreen frame. Once the workspace is
    /// shown, it's no longer parked, so that it stays where macOS puts it when the fullscreen ends
    @Test
    func aMacosFullscreenWindowIsNoLongerParkedOnceItsWorkspaceIsShown() {
        let workspace = setUpTree("h_tiles() macos_fullscreen(1)", workspace: "a")
        testWindow(1).rect = rect(0, 0, 1920, 1080)
        #expect(Workspace.get(byName: "b").focusWorkspace())
        world.platform.apply(placements())
        #expect(workspace.focusWorkspace())
        world.platform.apply(placements())

        testWindow(1).move(to: workspace.containerCreatingIfNeeded(.floating)) // The fullscreen ended
        testWindow(1).rect = rect(100, 100, 400, 300)
        world.platform.apply(placements())

        #expect(!fake.isParked(1))
        expectEqual(testWindow(1).rect, rect(100, 100, 400, 300))
    }

    /// A tile is read before its write, so that a tile at its frame isn't written again. A tile last seen at another frame
    /// than the layout's (by the last placement here, or by a read like the drag's in ResizeWithMouseTest) is written
    /// without the read
    @Test
    func aTileThatTheLayoutMovedIsWrittenWithoutARead() {
        let window = FakeWindow(app: testApp, rect: rect(0, 0, 400, 300), title: "1")
        fake.windows[1] = window
        let (left, right) = (rect(0, 0, 400, 300), rect(400, 0, 400, 300))
        func place(_ frame: Rect) -> [PlatformCall] {
            fake.resetCalls()
            fake.apply([.frame(1, topLeft: frame.topLeftCorner, size: frame.size)])
            return fake.calls
        }
        let write: (Rect) -> PlatformCall = { .frame(1, topLeft: $0.topLeftCorner, size: $0.size) }

        expectEqual(place(left), [.axRead(1)], "at its frame")
        expectEqual(place(right), [write(right)], "moved by the layout from where a read found it")
        expectEqual(place(left), [write(left)], "moved by the layout from where a write put it")
        expectEqual(place(left), [.axRead(1)], "at the same frame: the app may have moved it")
    }

    /// A light session's batch trusts what the last placements saw (a heavy refresh's P4 follows it): a tile last seen at
    /// its frame gets no AX call, while the command's moves are written. A tile that the app moved meanwhile stays there
    /// until P4. A size that the app rejects is written again by each P4, not by the light sessions in between
    @Test
    func aTrustingBatchWritesTheTilesThatTheLayoutMovedAndReadsNone() {
        let window = FakeWindow(app: testApp, rect: rect(0, 0, 400, 300), title: "1")
        fake.windows[1] = window
        let (left, wide) = (rect(0, 0, 400, 300), rect(0, 0, 800, 300))
        func place(_ frame: Rect, trusting: Bool) -> [PlatformCall] {
            fake.resetCalls()
            fake.apply([.frame(1, topLeft: frame.topLeftCorner, size: frame.size)], focus: nil, trustsLastSeen: trusting)
            return fake.calls
        }
        let write: (Rect) -> PlatformCall = { .frame(1, topLeft: $0.topLeftCorner, size: $0.size) }
        let movedByTheApp = rect(37, 37, 350, 300)

        expectEqual(place(left, trusting: false), [.axRead(1)], "checked at its frame")
        expectEqual(place(left, trusting: true), [], "trusted at its frame")
        window.rect = movedByTheApp
        expectEqual(place(left, trusting: true), [], "moved by the app: trusted")
        expectEqual(window.rect, movedByTheApp, "moved by the app: there until P4")
        expectEqual(place(left, trusting: false), [.axRead(1), write(left)], "moved by the app: put back by P4")
        expectEqual(place(wide, trusting: true), [write(wide)], "moved by the command")
        window.rect = rect(0, 0, 600, 300) // The app rejects the width
        expectEqual(place(wide, trusting: true), [], "a rejected size, in a light session")
        expectEqual(place(wide, trusting: false), [.axRead(1), write(wide)], "a rejected size, in P4")
    }

    /// A trusting batch reads a tile that AeroSpace or macOS may have put elsewhere since the tile was last seen at its
    /// frame, and writes a parked one without the read: an unpark is always written, so AxApp's shown job waits for it
    @Test
    func aTrustingBatchChecksATileThatWasPutElsewhereInAnotherWay() {
        let left = rect(0, 0, 400, 300)
        let tile: Placement = .frame(1, topLeft: left.topLeftCorner, size: left.size)
        let write: PlatformCall = .frame(1, topLeft: left.topLeftCorner, size: left.size)
        let floating = FloatingTarget(monitor: testMonitor, monitors: NonEmptyArray(testMonitor), isShown: true)
        let rows: [(name: String, between: () -> Void, calls: [PlatformCall])] = [
            ("placed as a floating window", { fake.apply([.floating(1, floating)]) }, [.axRead(1)]),
            ("its floating size restored", { fake.restoreFloatingSize(1) }, [.axRead(1), write]),
            ("a macOS fullscreen window", { fake.apply([.leave(1)]); fake.windows[1]?.rect = rect(0, 0, 1920, 1080) }, [.axRead(1), write]),
            ("parked", { fake.apply([.park(1, parkTarget(.bottomRightCorner, testMonitor))]) }, [write]),
        ]
        for row in rows {
            fake.windows[1] = FakeWindow(app: testApp, rect: rect(0, 0, 500, 400), title: "1") // At its floating size
            fake.apply([tile])
            row.between()
            fake.resetCalls()

            fake.apply([tile], focus: nil, trustsLastSeen: true)

            expectEqual(fake.calls, row.calls, "\(row.name)")
        }

        var state = PlacementState(lastFloatingSize: nil)
        let at = rect(100, 100, 400, 300) // Where StaleAfter is
        state.apply(.frame(1, topLeft: at.topLeftCorner, size: at.size), to: StaleAfter(calls: 100), trustsLastSeen: false)
        state.apply(.frame(1, topLeft: .zero, size: at.size), to: StaleAfter(calls: 1), trustsLastSeen: false) // Stale at its write
        let current = StaleAfter(calls: 100)
        state.apply(.frame(1, topLeft: at.topLeftCorner, size: at.size), to: current, trustsLastSeen: true)
        expectEqual(current.log.items, ["rect"], "a write that turned stale")
    }

    /// A trusting batch doesn't read a window that the last park sent to the bottom right corner's x: a parks job that
    /// writes nothing doesn't wait for the shown jobs either. A window that the app moved meanwhile stays there until P4.
    /// The bottom left corner's x depends on the size, which only a read tells. A park to another corner (e.g., a monitor
    /// was added on the right), or after a park whose write turned stale, reads and writes
    @Test
    func aTrustingBatchDoesntReadAWindowParkedInTheBottomRightCorner() {
        let monitors = NonEmptyArray(testMonitor, [rightTestMonitor])
        let bottomRight = parkTarget(.bottomRightCorner, testMonitor, monitors)
        let bottomLeft = parkTarget(.bottomLeftCorner, testMonitor, monitors)
        let otherMonitor = parkTarget(.bottomRightCorner, rightTestMonitor, monitors)
        let movedByTheApp = rect(1880, 1079, 400, 300)
        let rows: [(name: String, first: ParkTarget, movedTo: Rect?, next: ParkTarget, trusts: Bool, calls: [PlatformCall])] = [
            ("in its corner", bottomRight, nil, bottomRight, true, []),
            ("moved by the app", bottomRight, movedByTheApp, bottomRight, true, []),
            ("moved by the app, in P4", bottomRight, movedByTheApp, bottomRight, false, [.axRead(1), .frame(1, topLeft: CGPoint(x: 1919, y: 1079), size: nil)]),
            ("in the bottom left corner", bottomLeft, nil, bottomLeft, true, [.axRead(1)]),
            ("to the bottom left corner", bottomRight, nil, bottomLeft, true, [.axRead(1), .frame(1, topLeft: CGPoint(x: -399, y: 1079), size: nil)]),
            ("to another monitor's corner", bottomRight, nil, otherMonitor, true, [.axRead(1), .frame(1, topLeft: CGPoint(x: 3839, y: 1079), size: nil)]),
        ]
        for row in rows {
            fake.windows[1] = FakeWindow(app: testApp, rect: rect(100, 100, 400, 300), title: "1")
            fake.apply([.park(1, row.first)])
            if let movedTo = row.movedTo { fake.windows[1]?.rect = movedTo }
            fake.resetCalls()

            fake.apply([.park(1, row.next)], focus: nil, trustsLastSeen: row.trusts)

            expectEqual(fake.calls, [.park(1, row.next)] + row.calls, "\(row.name)")
        }

        var state = PlacementState(lastFloatingSize: nil)
        state.apply(.park(1, bottomRight), to: StaleAfter(calls: 1), trustsLastSeen: false) // Stale at its write
        let current = StaleAfter(calls: 100)
        state.apply(.park(1, bottomRight), to: current, trustsLastSeen: true)
        expectEqual(current.log.items, ["rect", "setFrame"], "after a park whose write turned stale")
    }

    /// A placement made stale by a newer write of the window stops before its next AX call. An unpark that didn't write the
    /// position leaves the window parked, so the next placement unparks it. Termination stops them the same way
    @Test
    func aStalePlacementStopsBeforeItsNextAxCallAndAStaleUnparkKeepsTheWindowParked() {
        var state = PlacementState(lastFloatingSize: nil)
        let target = FloatingTarget(monitor: testMonitor, monitors: NonEmptyArray(testMonitor), isShown: true)
        state.apply(.park(1, parkTarget(.bottomRightCorner, testMonitor)), to: StaleAfter(calls: 100), trustsLastSeen: false)

        let stale = StaleAfter(calls: 0)
        state.apply(.park(1, parkTarget(.bottomRightCorner, testMonitor)), to: stale, trustsLastSeen: false)
        state.apply(.frame(1, topLeft: .zero, size: CGSize(width: 400, height: 300)), to: stale, trustsLastSeen: false)
        state.apply(.floating(1, target), to: stale, trustsLastSeen: false)
        expectEqual(stale.log.items, [])

        let staleAtTheWrite = StaleAfter(calls: 1)
        state.apply(.floating(1, target), to: staleAtTheWrite, trustsLastSeen: false)
        expectEqual(staleAtTheWrite.log.items, [])
        #expect(state.isParked)

        let current = StaleAfter(calls: 100)
        state.apply(.floating(1, target), to: current, trustsLastSeen: false)
        #expect(!state.isParked)
        expectEqual(current.log.items.first, "setFrame")
    }

    private func parkTarget(
        _ corner: OptimalHideCorner,
        _ monitor: MonitorInfo,
        _ monitors: NonEmptyArray<MonitorInfo>? = nil,
        isFloating: Bool = false,
    ) -> ParkTarget {
        ParkTarget(corner: corner, monitor: monitor, monitors: monitors ?? NonEmptyArray(monitor), isFloating: isFloating, isZoom: false)
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

    func rect() -> Rect? {
        log.append("rect")
        return Rect(topLeftX: 100, topLeftY: 100, width: 400, height: 300)
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
