import AppKit
import Common
import Foundation
import os

nonisolated let signposter = OSSignposter(subsystem: aeroSpaceAppId, category: .pointsOfInterest)

let myPid = NSRunningApplication.current.processIdentifier
nonisolated let lockScreenAppBundleId = "com.apple.loginwindow"

private var signalSources: [any DispatchSourceSignal] = [] // A released source stops delivering the signal

func interceptTermination(_ sig: Int32) {
    // A signal handler may only call async-signal-safe functions, and it runs on any thread.
    // Ignore the signal instead (the dispatch source still sees it), and handle it on the main queue
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler { // On the main queue, so the closure is main actor isolated
        terminationHandler?.beforeTermination()
        exit(sig)
    }
    source.resume()
    signalSources.append(source)
}

func initTerminationHandler() {
    unsafe _terminationHandler = AppServerTerminationHandler()
}

private struct AppServerTerminationHandler: TerminationHandler {
    func beforeTermination() {
        // Make all windows fullscreen before Quit
        for window in MacWindow.allWindowsMap.values {
            // makeAllWindowsVisibleAndRestoreSize may be invoked when something went wrong (e.g. some windows are unbound)
            // that's why it's not allowed to use `.parent` call in here
            let monitor = window.macApp.getAxRectForTermination(window.windowId)?.center.monitorApproximation ?? mainMonitorInfo
            let monitorVisibleRect = monitor.visibleRect
            let windowSize = window.lastFloatingSize ?? CGSize(width: monitorVisibleRect.width, height: monitorVisibleRect.height)
            let point = CGPoint(
                x: monitorVisibleRect.topLeftX + (monitorVisibleRect.width - windowSize.width) / 2,
                y: monitorVisibleRect.topLeftY + (monitorVisibleRect.height - windowSize.height) / 2,
            )
            window.macApp.setAxFrameForTermination(window.windowId, point, windowSize)
        }
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

func terminateApp() -> Never {
    NSApplication.shared.terminate(nil)
    die("Unreachable code")
}

func - (a: CGPoint, b: CGPoint) -> CGPoint {
    CGPoint(x: a.x - b.x, y: a.y - b.y)
}

func + (a: CGPoint, b: CGPoint) -> CGPoint {
    CGPoint(x: a.x + b.x, y: a.y + b.y)
}

extension CGPoint {
    func distance(toOuterFrame rect: Rect) -> CGFloat {
        // Subtract 1 from maxX/maxY because the right/bottom bounds are
        // exclusive.
        let dx = max(rect.minX - x, 0, x - (rect.maxX - 1))
        let dy = max(rect.minY - y, 0, y - (rect.maxY - 1))
        return CGPoint(x: dx, y: dy).vectorLength
    }

    func coerce(in rect: Rect) -> CGPoint? {
        guard let xRange = rect.minX.until(incl: rect.maxX - 1) else { return nil }
        guard let yRange = rect.minY.until(incl: rect.maxY - 1) else { return nil }
        return CGPoint(x: x.coerce(in: xRange), y: y.coerce(in: yRange))
    }

    func addingOffset(_ orientation: Orientation, _ offset: CGFloat) -> CGPoint {
        orientation == .h ? CGPoint(x: x + offset, y: y) : CGPoint(x: x, y: y + offset)
    }

    func getProjection(_ orientation: Orientation) -> Double { orientation == .h ? x : y }

    var vectorLength: CGFloat { sqrt(x * x + y * y) }

    // Fall back to mainMonitorInfo if there are no screens (e.g., during display reconfiguration) to avoid crash
    var monitorApproximation: MonitorInfo { monitorInfos.minBy { distance(toOuterFrame: $0.rect) } ?? mainMonitorInfo }

    var withYAxisFlipped: CGPoint {
        consuming get {
            self.y = mainMonitorInfo.height - self.y
            return self
        }
    }
}

extension CGFloat {
    func div(_ denominator: Int) -> CGFloat? {
        denominator == 0 ? nil : self / CGFloat(denominator)
    }

    func coerce(in range: ClosedRange<CGFloat>) -> CGFloat {
        switch true {
            case self > range.upperBound: range.upperBound
            case self < range.lowerBound: range.lowerBound
            default: self
        }
    }
}

#if DEBUG
    nonisolated let isDebug = true
#else
    nonisolated let isDebug = false
#endif

nonisolated func checkCancellation(_ cm: CancellationMode = .cancellable) throws(CancellationError) {
    if cm == .cancellable && Task.isCancelled {
        throw CancellationError()
    }
}

nonisolated enum CancellationMode: Equatable, Sendable {
    case cancellable
    case nonCancellable
}
