import AppKit

/// How the frontmost app activated: with a click or with the keyboard, see ``AxApp/focusedWindow(isClickActivation:)``.
/// A click on Finder's desktop activates Finder, which focuses the desktop, as it does after cmd-tab while its windows
/// are all on the parking desktop. The last input event before the activation tells them apart: a left mouse down, or a
/// key down (cmd-tab, Spotlight's return, a hotkey). Not a time window since the click: the notification comes late
/// while main is busy
final class Activations {
    private var clickActivated: pid_t? = nil

    init(observing center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        // The center keeps the observer until it's removed, and the platform lives as long as AeroSpace
        _ = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            let isClick = secondsSinceLast(.leftMouseDown) < secondsSinceLast(.keyDown)
            MainActor.assumeIsolated { self?.clickActivated = isClick ? pid : nil } // The queue is .main
        }
    }

    /// The app's latest activation came with a click. false for an app that hasn't activated since AeroSpace started
    func isClickActivation(of pid: pid_t) -> Bool { clickActivated == pid }
}

nonisolated private func secondsSinceLast(_ type: CGEventType) -> CFTimeInterval {
    CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
}
