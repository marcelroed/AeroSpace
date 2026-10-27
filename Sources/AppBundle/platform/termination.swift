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
/// floating size or the monitor's visible size (``TerminationMonitors``)
func restoreWindowsOnMainThread(_ windows: [(app: AxApp, windowId: UInt32)], _ monitors: TerminationMonitors) {
    var timedOutApps: Set<pid_t> = []
    for (app, windowId) in windows where !timedOutApps.contains(app.pid) {
        let isDone = app.postAndWait(timeout: terminationAxTimeout) { app in app.restore(windowId, monitors) }
        if !isDone {
            timedOutApps.insert(app.pid)
        }
    }
}

/// A die off the main thread (e.g. on an AX thread) can't read the tree. It restores every window that the apps know, as
/// the main thread does: one job per app, all in parallel, against one deadline. It skips the app whose thread is dying:
/// that thread would never run the job
nonisolated func restoreWindowsOffMainThread(_ apps: [AxApp], _ monitors: TerminationMonitors) {
    let deadline: DispatchTime = .now() + terminationAxTimeout
    let restores = DispatchGroup()
    for app in apps where !app.isCurrentThread {
        restores.enter()
        app.post { app in
            for windowId in app.windowIds {
                app.restore(windowId, monitors)
            }
            restores.leave()
        }
    }
    _ = restores.wait(timeout: deadline)
}

/// The monitors that termination restores the windows onto: the last snapshot with screens, which
/// ``LivePlatform/monitors()`` publishes for a die off the main thread too. Sendable: the AX threads compute the frames
nonisolated struct TerminationMonitors: Sendable {
    /// Sorted as ``Monitors/all``
    let all: NonEmptyArray<MonitorInfo>
    let main: MonitorInfo

    /// Centered on the visible rect of the monitor nearest to the window's center (as `Monitors.approximation`), or of the
    /// main monitor
    func restoreFrame(windowRect: Rect?, _ lastFloatingSize: CGSize?) -> (topLeft: CGPoint, size: CGSize) {
        let monitor = windowRect.map { nearestMonitor(to: $0.center, in: all) } ?? main
        let visibleRect = monitor.visibleRect
        let size = lastFloatingSize ?? CGSize(width: visibleRect.width, height: visibleRect.height)
        let topLeft = CGPoint(
            x: visibleRect.topLeftX + (visibleRect.width - size.width) / 2,
            y: visibleRect.topLeftY + (visibleRect.height - size.height) / 2,
        )
        return (topLeft, size)
    }
}
