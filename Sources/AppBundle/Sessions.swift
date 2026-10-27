import AppKit
import Common

/// The funnel for every session: each input that reads or changes the model enters through one of these methods.
/// - Hotkeys, the CLI server, the menu and config auto-reload call ``light(_:_:body:)``.
/// - GlobalObserver calls ``onWorkspaceNotification(_:)``, ``onAppHidden()`` and ``onLeftMouseUp()``.
/// - The AX observer callbacks call ``onAxEvent(pid:_:)``, the focus-follows-mouse monitor calls ``onMouseMoved(to:)``.
///
/// A light session runs a command-like body between two model refreshes, lays out the workspaces and schedules a heavy
/// refresh. A heavy refresh also re-reads the windows of all apps from macOS (it registers new windows and garbage
/// collects closed ones), then lays out the workspaces.
///
/// How concurrent work coalesces. The code follows this table:
///
/// | Work                          | Mechanism                                             | Preempted by                          |
/// |-------------------------------|-------------------------------------------------------|---------------------------------------|
/// | Heavy refresh                 | `heavy`, a ``LatestTaskSlot``                         | A newer heavy refresh, a light session |
/// | Light session                 | Runs at once in its caller's task, cancels `heavy`    | — (but see the next row)              |
/// | ffm, mouse move, mouse resize | One ``LatestTaskSlot`` per kind around a light session | A newer event of the same kind       |
/// | AX read of a heavy refresh    | An observe read of ``Platform`` (`AxApp.call`): abandonable | Cancellation of the heavy refresh: it returns at once |
/// | AX read of a command          | A single read of ``Platform`` (`AxApp.run`): awaited  | —                                     |
/// | Frame write                   | `AxApp.postWindowWrite`: a generation per window      | A newer frame write, attribute write or close of it |
/// | Native focus (slow path)      | A post with a global generation (`LivePlatform.focus`) | A newer native focus                 |
/// | App registration              | One pending task per pid (`LivePlatform.pendingRegistrations`); a failed one backs off 1–60 s | — |
/// | Order within an app           | FIFO on its actor's thread (posts and awaited calls share one queue): the visible workspaces' frames, then hiding in corners, then focus | — |
///
/// A cancelled heavy refresh stops at its next cancellation check: an observe read or a layout step. Nothing is
/// queued for retry: the tree is the desired state, and every heavy refresh lays out every window again.
final class Sessions {
    private let heavy = LatestTaskSlot()
    private let focusFollowsMouse = LatestTaskSlot()
    private let mouseMove = LatestTaskSlot()
    private let mouseResize = LatestTaskSlot()

    // MARK: Light sessions and heavy refreshes

    /// Runs `body` as a light session. It cancels the scheduled heavy refresh, and schedules a new one after the layout
    /// (except for focus-follows-mouse)
    func light<T>(
        _ event: RefreshSessionEvent,
        _: RunSessionGuard,
        body: () async throws -> T,
    ) async throws -> T {
        let state = signposter.beginInterval(#function, "event: \(event)")
        defer { signposter.endInterval(#function, state) }
        cancelHeavy() // Give priority to the light session
        updateMonitors() // While there are no screens, the commands fail with a message or work on the last monitors
        startWindowLevelCacheSession()
        return try await $refreshSessionEvent.withValue(event) {
            try await syncFocusFromMacOs()
            let focusBefore = focus.windowOrNil

            await refreshModel_nonCancellable()
            let result = try await body()
            await refreshModel_nonCancellable()

            let focusAfter = focus.windowOrNil

            // Runs at the next suspension point, so the layout dispatches the frames of the visible windows first
            // (updateTrayText does launchservicesd IPC), and the tray doesn't wait for the AX calls that the layout awaits
            Task.startUnstructured {
                updateTrayText()
                world.ui.secureInputPanel.refresh()
            }
            if !event.isFocusFollowsMouse { try await layoutWorkspaces() }
            if focusBefore != focusAfter {
                focusAfter?.nativeFocus() // syncFocusToMacOs
            }
            if !event.isFocusFollowsMouse { scheduleHeavy(event) }
            return result
        }
    }

    /// Replaces the scheduled heavy refresh with a new one. `preLayout`: lay out the workspaces before the windows are
    /// re-read too, so that an app activation shows its workspace without waiting for all apps
    func scheduleHeavy(_ event: RefreshSessionEvent, preLayout: Bool = false) {
        heavy.replace { [self] in
            try checkCancellation()
            await runHeavy(event, isCancellable: true, preLayout: preLayout)
        }
    }

    func cancelHeavy() { heavy.cancel() }

    /// The first sessions after the launch. The heavy refresh registers the windows that are already open without
    /// moving them. It isn't cancellable, so that `isStartup` reaches every on-window-detected callback. Then a light
    /// session lays them out and runs `body`
    func startup(_ body: () async throws -> ()) async throws {
        await runHeavy(.startup, isCancellable: false, layoutWorkspaces: false)
        try await light(.startup, .forceRun, body: body)
    }

    private func runHeavy(
        _ event: RefreshSessionEvent,
        isCancellable: Bool,
        layoutWorkspaces shouldLayoutWorkspaces: Bool = true,
        preLayout: Bool = false,
    ) async {
        let state = signposter.beginInterval(#function, "event: \(event)")
        defer { signposter.endInterval(#function, state) }
        if !world.isEnabled { return }
        // No screens (e.g., during display reconfiguration): nothing can be laid out. Skip the session, the next one catches
        // up when the screens come back
        if !updateMonitors() { return }
        startWindowLevelCacheSession()
        do {
            try await $refreshSessionEvent.withValue(event) {
                try await syncFocusFromMacOs()

                if shouldLayoutWorkspaces && preLayout { try await layoutWorkspaces() }

                await refreshModel_nonCancellable()
                try await refresh()

                updateTrayText()
                world.ui.secureInputPanel.refresh()
                try await normalizeLayoutReason()
                if shouldLayoutWorkspaces { try await layoutWorkspaces() }
            }
        } catch let err as CancellationError {
            check(isCancellable, "Non cancellable refresh session was canceled: \(err) (\(type(of: err)))")
        } catch {
            die("Illegal error: \(error)")
        }
    }

    // MARK: AX notifications

    /// The entry point of the AX observers. On the app's AX thread, the observer callback maps the notification to an
    /// ``AxEvent``, then calls this on the main actor:
    /// `Task.startUnstructured { @MainActor in await world.sessions.onAxEvent(pid: pid, event) }`.
    /// - `pid`: the app whose observer fired. Unused for now: every event except a mouse drag refreshes all apps.
    /// - Ignored while AeroSpace is disabled.
    /// - `.moved` / `.resized` of the window that the user drags or resizes with the mouse: a light session follows the
    ///   mouse (one ``LatestTaskSlot`` per kind). Any other event, e.g. a window that the layout moved: a heavy refresh.
    func onAxEvent(pid _: pid_t, _ event: AxEvent) async {
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        let sessionEvent: RefreshSessionEvent = .ax("\(event)")
        switch event {
            case .windowCreated, .focusedWindowChanged, .destroyed, .miniaturized, .deminiaturized:
                scheduleHeavy(sessionEvent)
            case .moved(let windowId):
                await onMovedOrResized(windowId, sessionEvent, mouseMove, token, moveWithMouse)
            case .resized(let windowId):
                await onMovedOrResized(windowId, sessionEvent, mouseResize, token, resizeWithMouse)
        }
    }

    private func onMovedOrResized(
        _ windowId: WindowId?,
        _ event: RefreshSessionEvent,
        _ slot: LatestTaskSlot,
        _ token: RunSessionGuard,
        _ manipulateWithMouse: @escaping (Window) async throws -> (),
    ) async {
        guard let windowId, let window = Window.get(byId: windowId), await isManipulatedWithMouse(window) else {
            scheduleHeavy(event)
            return
        }
        slot.replace { [self] in
            try checkCancellation()
            try await light(event, token) {
                guard window.isAlive else { return } // The window closed at a suspension point
                try await manipulateWithMouse(window)
            }
        }
    }

    // MARK: NSWorkspace and global mouse events (GlobalObserver), focus-follows-mouse

    /// An app launched, activated, unhid or terminated, the active space changed, or the displays changed
    func onWorkspaceNotification(_ name: Notification.Name) {
        if !world.isEnabled { return }
        scheduleHeavy(.globalObserver(name.rawValue), preLayout: name == NSWorkspace.didActivateApplicationNotification)
    }

    /// An app was hidden (cmd-h or cmd-alt-h)
    func onAppHidden() async throws {
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        try await light(.globalObserver(NSWorkspace.didHideApplicationNotification.rawValue), token) {
            unhideMacosHiddenAppsIfConfigured()
        }
    }

    func onLeftMouseUp() async throws {
        // todo reduce number of refreshSession in the callback
        //  resetManipulatedWithMouseIfPossible might call its own refreshSession
        //  The end of the callback calls refreshSession
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        try await resetManipulatedWithMouseIfPossible()
        let mouseLocation = world.platform.mouseLocation
        let clickedMonitor = world.monitors.approximation(mouseLocation)
        switch true {
            // Detect clicks on desktop of different monitors
            case clickedMonitor.visibleRect.contains(mouseLocation) && clickedMonitor.activeWorkspace != focus.workspace:
                _ = try await light(.globalObserverLeftMouseUp, token) {
                    clickedMonitor.activeWorkspace.focusWorkspace()
                }
            // Detect close button clicks for unfocused windows. Yes, kAXUIElementDestroyedNotification is that unreliable
            //  And trigger new window detection that could be delayed due to mouseDown event
            default:
                scheduleHeavy(.globalObserverLeftMouseUp)
        }
    }

    /// The mouse moved while focus-follows-mouse is on
    func onMouseMoved(to location: CGPoint) {
        focusFollowsMouse.replace { try await focusWindow(underMouse: location) }
    }

    /// Focus-follows-mouse was turned off: drop the pending focus change
    func cancelFocusFollowsMouse() { focusFollowsMouse.cancel() }
}

/// Proof that AeroSpace is enabled, or that the session may run anyway (`enable`, the startup, the menu's Enable button).
/// A light session takes one, so that no entry point forgets the check
struct RunSessionGuard: Sendable {
    static var isServerEnabled: RunSessionGuard? { world.isEnabled ? forceRun : nil }
    static func isServerEnabled(orIsEnableCommand command: (any Command)?) -> RunSessionGuard? {
        command is EnableCommand ? .forceRun : .isServerEnabled
    }
    static let forceRun = RunSessionGuard()
    private init() {}
}

/// An AX notification, as an app's AX observer reports it to ``Sessions/onAxEvent(pid:_:)``. It crosses from the app's AX
/// thread to the main actor
nonisolated enum AxEvent: Sendable, Equatable {
    /// kAXWindowCreatedNotification, observed on the app
    case windowCreated
    /// kAXFocusedWindowChangedNotification, observed on the app
    case focusedWindowChanged
    /// kAXUIElementDestroyedNotification, observed on a window
    case destroyed
    /// kAXWindowMiniaturizedNotification, observed on a window
    case miniaturized
    /// kAXWindowDeminiaturizedNotification, observed on a window
    case deminiaturized
    /// kAXMovedNotification, observed on a window: by the user's mouse, by AeroSpace's layout or by the app itself.
    /// The window's id, nil if AX can't tell it (e.g. the window is being destroyed)
    case moved(windowId: WindowId?)
    /// kAXResizedNotification, observed on a window. Same as `moved`
    case resized(windowId: WindowId?)
}
