import AppKit
import Common

/// The NSWorkspace notifications, the display changes and the global left mouse up. Each one goes to its handler in
/// ``Sessions``
enum GlobalObserver {
    // NotificationCenter calls these with a nonisolated closure type, even on the main queue
    nonisolated private static func onNotif(_ notification: Notification) {
        // Third line of defence against lock screen window. See: closedWindowsCache
        // Second and third lines of defence are technically needed only to avoid potential flickering
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if app?.bundleIdentifier == lockScreenAppBundleId { return }
        let name = notification.name
        Task.startUnstructured { @MainActor in
            world.sessions.onWorkspaceNotification(name)
        }
    }

    nonisolated private static func onHideApp(_: Notification) {
        Task.startUnstructured { @MainActor in
            try await world.sessions.onAppHidden()
        }
    }

    static func initObserver() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.didHideApplicationNotification, object: nil, queue: .main, using: onHideApp)
        nc.addObserver(forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main, using: onNotif)
        // A display was plugged in, unplugged, rearranged or woke up. The heavy refresh takes a new snapshot of the monitors
        NotificationCenter.default
            .addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: onNotif)

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            Task.startUnstructured { @MainActor in
                try await world.sessions.onLeftMouseUp()
            }
        }
    }
}

/// With `automatically-unhide-macos-hidden-apps`, unhides the apps that the user hid. The body of the light session of
/// ``Sessions/onAppHidden()``
func unhideMacosHiddenAppsIfConfigured() {
    if !config.automaticallyUnhideMacosHiddenApps { return }
    if let w = prevFocus?.windowOrNil,
       world.platform.isHidden(w.app),
       // "Hide others" (cmd-alt-h) -> don't force focus
       // "Hide app" (cmd-h) -> force focus
       world.platform.runningApps().count(where: world.platform.isHidden) == 1
    {
        // Force focus
        _ = w.focusWindow()
        w.nativeFocus()
    }
    for app in world.platform.runningApps() {
        world.platform.unhideApp(app)
    }
}
