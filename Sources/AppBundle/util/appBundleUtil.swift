import AppKit
import Common
import Foundation
import os

nonisolated let signposter: OSSignposter = OSSignposter(subsystem: aeroSpaceAppId, category: .pointsOfInterest)

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

func terminateApp() -> Never {
    NSApplication.shared.terminate(nil)
    die("Unreachable code")
}

nonisolated func - (a: CGPoint, b: CGPoint) -> CGPoint {
    CGPoint(x: a.x - b.x, y: a.y - b.y)
}

nonisolated func + (a: CGPoint, b: CGPoint) -> CGPoint {
    CGPoint(x: a.x + b.x, y: a.y + b.y)
}

extension CGPoint {
    nonisolated func distance(toOuterFrame rect: Rect) -> CGFloat {
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

    nonisolated var vectorLength: CGFloat { sqrt(x * x + y * y) }

    var withYAxisFlipped: CGPoint {
        consuming get {
            self.y = world.monitors.main.height - self.y
            return self
        }
    }
}

extension CGFloat {
    func div(_ denominator: Int) -> CGFloat? {
        denominator == 0 ? nil : self / CGFloat(denominator)
    }

    nonisolated func coerce(in range: ClosedRange<CGFloat>) -> CGFloat {
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

nonisolated func checkCancellation() throws(CancellationError) {
    if Task.isCancelled {
        throw CancellationError()
    }
}
