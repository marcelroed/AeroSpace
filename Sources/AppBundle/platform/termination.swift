import AppKit
import Common
import Synchronization

/// How long termination waits for one window of an app (one job: read its rect, then write its frame). After an app's
/// first timeout, its remaining windows are skipped: they stay where AeroSpace hid them, but a hung app can't stop
/// AeroSpace from exiting (RB-76)
nonisolated private let terminationAxTimeout: DispatchTimeInterval = .seconds(2)

/// Set once termination starts. From then on, pending placements are skipped, so that they can't move a restored window
/// again
nonisolated let isTerminating: Atomic<Bool> = Atomic(false)

struct AppServerTerminationHandler: TerminationHandler {
    func beforeTermination() {
        isTerminating.store(true, ordering: .sequentiallyConsistent)
        restoreWindowsOnMainThread()
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
private func restoreWindowsOnMainThread() {
    let monitors = TerminationMonitors(
        all: monitorInfos.map { TerminationMonitor(rect: $0.rect, visibleRect: $0.visibleRect) },
        main: TerminationMonitor(rect: mainMonitorInfo.rect, visibleRect: mainMonitorInfo.visibleRect),
    )
    var timedOutApps: Set<pid_t> = []
    for window in MacWindow.allWindowsMap.values {
        // makeAllWindowsVisibleAndRestoreSize may be invoked when something went wrong (e.g. some windows are unbound)
        // that's why it's not allowed to use `.parent` call in here
        guard let app = window.macApp.axForTermination, !timedOutApps.contains(app.pid) else { continue }
        let windowId = window.windowId
        let lastFloatingSize = window.lastFloatingSize
        let isDone = app.postAndWait(timeout: terminationAxTimeout) { app in
            app.restore(windowId) { monitors.restoreFrame(windowRect: $0, lastFloatingSize) }
        }
        if !isDone {
            timedOutApps.insert(app.pid)
        }
    }
}

nonisolated private struct TerminationMonitor {
    let rect: Rect
    let visibleRect: Rect
}

/// The monitors to restore windows onto. Sendable, so that the AX threads compute the frames
nonisolated private struct TerminationMonitors {
    let all: [TerminationMonitor]
    let main: TerminationMonitor

    /// Centered on the monitor nearest to the window's center (as `monitorApproximation`), or the main monitor
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
}
