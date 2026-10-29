import AppKit

/// RB-113: after an app's AX subscription fails, the refresh's bulk scan retries its registration after 1 s, then 2 s,
/// 4 s, … up to 60 s, instead of on every refresh. Launching, activating or terminating the app forgets its failures
final class RegistrationBackoffs {
    private var backoffs: [pid_t: (delay: Duration, retryAt: ContinuousClock.Instant)] = [:]

    init(observing center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        for name in names {
            // The center keeps the observer until it's removed, and the platform lives as long as AeroSpace
            _ = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let pid = app.processIdentifier
                MainActor.assumeIsolated { self?.forget(pid) } // The queue is .main
            }
        }
    }

    func isBackingOff(_ pid: pid_t, now: ContinuousClock.Instant = .now) -> Bool {
        backoffs[pid].map { now < $0.retryAt } ?? false
    }

    func failed(_ pid: pid_t, now: ContinuousClock.Instant = .now) {
        let delay = backoffs[pid].map { min($0.delay * 2, .seconds(60)) } ?? .seconds(1)
        backoffs[pid] = (delay, now + delay)
    }

    func forget(_ pid: pid_t) {
        backoffs[pid] = nil
    }
}
