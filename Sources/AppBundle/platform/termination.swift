import AppKit
import Common
import Synchronization

/// How long termination waits for the apps, so that a hung app can't stop AeroSpace from exiting (RB-76). The windows it
/// doesn't reach stay where AeroSpace hid them.
/// - On main: per window (one job: read its rect, then write its frame). After an app's first timeout, its remaining
///   windows are skipped.
/// - Off main: once for all apps, whose jobs run in parallel on their threads
nonisolated private let terminationAxTimeout: DispatchTimeInterval = .seconds(2)

/// Set once termination starts. From then on, pending placements are skipped, so that they can't move a restored window
/// again (a die off the main thread leaves the main actor running)
nonisolated let isTerminating: Atomic<Bool> = Atomic(false)

nonisolated struct AppServerTerminationHandler: TerminationHandler {
    let platform: any Platform

    /// On the dying thread, which can be any thread, or on main when quitting (the menu, SIGINT, SIGTERM). It never waits
    /// for the main thread
    func beforeTermination() {
        // A die already claimed it when it calls this. Quitting claims it here
        if claimTermination() == .otherThread {
            parkForever() // Another thread restores the windows and ends the process
        }
        isTerminating.store(true, ordering: .sequentiallyConsistent)
        platform.restoreForTermination()
        if isDebug {
            let semaphore = DispatchSemaphore(value: 0)
            // Use Task.detached to avoid inheriting @MainActor, and a nonisolated function.
            // On the main actor, it would cause a deadlock
            Task.detached {
                await toggleReleaseServerIfDebug(.on)
                semaphore.signal()
            }
            semaphore.wait()
        }
    }
}

/// Makes every window visible before quitting: centered on the monitor it's on (or the main monitor), at its last
/// floating size or the monitor's visible size
func restoreWindowsOnMainThread(_ windows: [(app: AxApp, windowId: UInt32)]) {
    let monitors = TerminationMonitors(
        all: world.monitors.all.map { TerminationMonitor(rect: $0.rect, visibleRect: $0.visibleRect) },
        main: TerminationMonitor(rect: world.monitors.main.rect, visibleRect: world.monitors.main.visibleRect),
    )
    var timedOutApps: Set<pid_t> = []
    for (app, windowId) in windows where !timedOutApps.contains(app.pid) {
        let isDone = app.postAndWait(timeout: terminationAxTimeout) { app in
            app.restore(windowId) { monitors.restoreFrame(windowRect: $0, $1) }
        }
        if !isDone {
            timedOutApps.insert(app.pid)
        }
    }
}

/// A die off the main thread (e.g. on an AX thread) can't read the tree or NSScreen. It restores every window that the
/// apps know at the size of its CoreGraphics display (no last floating size, no visible frame): one job per app, all in
/// parallel, against one deadline. It skips the app whose thread is dying: that thread would never run the job
nonisolated func restoreWindowsOffMainThread(_ apps: [AxApp]) {
    // todo M2-AXP: restore with main's geometry (the monitors' visible rects, lastFloatingSize) instead of the full
    //              display bounds
    guard let monitors = TerminationMonitors.fromCoreGraphics() else { return } // No display: 0x0 frames would be worse
    let deadline: DispatchTime = .now() + terminationAxTimeout
    let restores = DispatchGroup()
    for app in apps where !app.isCurrentThread {
        restores.enter()
        app.post { app in
            for windowId in app.windowIds {
                app.restore(windowId) { rect, _ in monitors.restoreFrame(windowRect: rect, nil) }
            }
            restores.leave()
        }
    }
    _ = restores.wait(timeout: deadline)
}

nonisolated private struct TerminationMonitor {
    let rect: Rect
    let visibleRect: Rect
}

/// The monitors to restore windows onto. Sendable, so that the AX threads compute the frames
nonisolated private struct TerminationMonitors {
    let all: [TerminationMonitor]
    let main: TerminationMonitor

    /// Centered on the monitor nearest to the window's center (as `Monitors.approximation`), or the main monitor
    func restoreFrame(windowRect: Rect?, _ lastFloatingSize: CGSize?) -> (topLeft: CGPoint, size: CGSize) {
        let monitor = windowRect.flatMap { nearestMonitor(to: $0) } ?? main
        let visibleRect = monitor.visibleRect
        let size = lastFloatingSize ?? CGSize(width: visibleRect.width, height: visibleRect.height)
        let topLeft = CGPoint(
            x: visibleRect.topLeftX + (visibleRect.width - size.width) / 2,
            y: visibleRect.topLeftY + (visibleRect.height - size.height) / 2,
        )
        return (topLeft, size)
    }

    /// `CGPoint.distance(toOuterFrame:)` is main actor isolated, so this repeats it (squared, which keeps the order)
    private func nearestMonitor(to windowRect: Rect) -> TerminationMonitor? {
        let x = windowRect.topLeftX + windowRect.width / 2
        let y = windowRect.topLeftY + windowRect.height / 2
        return all.minBy { monitor in
            let rect = monitor.rect
            let dx = max(rect.topLeftX - x, 0, x - (rect.topLeftX + rect.width - 1))
            let dy = max(rect.topLeftY - y, 0, y - (rect.topLeftY + rect.height - 1))
            return dx * dx + dy * dy
        }
    }

    /// CoreGraphics' global display coordinates have AX's origin and orientation. nil without an active display (e.g.
    /// during display reconfiguration)
    static func fromCoreGraphics() -> TerminationMonitors? {
        var count: UInt32 = 0
        _ = unsafe CGGetActiveDisplayList(0, nil, &count)
        if count == 0 { return nil }
        var displays: [CGDirectDisplayID] = Array(repeating: 0, count: Int(count))
        _ = unsafe CGGetActiveDisplayList(count, &displays, &count)
        func monitor(_ display: CGDirectDisplayID) -> TerminationMonitor {
            let bounds = CGDisplayBounds(display)
            let rect = Rect(topLeftX: bounds.minX, topLeftY: bounds.minY, width: bounds.width, height: bounds.height)
            return TerminationMonitor(rect: rect, visibleRect: rect)
        }
        return TerminationMonitors(all: displays.prefix(Int(count)).map(monitor), main: monitor(CGMainDisplayID()))
    }
}
