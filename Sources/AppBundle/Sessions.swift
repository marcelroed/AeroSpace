import AppKit
import Common

/// The funnel for every session: each input that reads or changes the model enters through one of these methods.
/// - Hotkeys, the CLI server, the menu and config auto-reload call ``light(_:_:body:)``.
/// - GlobalObserver calls ``onWorkspaceNotification(_:)``, ``onAppHidden()`` and ``onLeftMouseUp()``.
/// - The AX observer callbacks call ``onAxEvent(_:)``, the focus-follows-mouse monitor calls ``onMouseMoved(to:)``.
///
/// A light session runs a command-like body between two model refreshes, presents and schedules a heavy refresh. A heavy
/// refresh re-reads the windows of all apps from macOS (it registers new windows and garbage collects closed ones), then
/// presents. Reconcile.swift has their phases.
///
/// How concurrent work coalesces. The code follows this table:
///
/// | Work                          | Mechanism                                             | Preempted by                          |
/// |-------------------------------|-------------------------------------------------------|---------------------------------------|
/// | Heavy refresh                 | `heavy`, a ``LatestTaskSlot``                         | A newer heavy refresh, a light session: P1 stops, P3 runs to the end, P4 is skipped |
/// | Startup heavy refresh         | Awaited in ``startup(_:)``, outside the slot; it skips P4 | Nothing                           |
/// | Light session                 | Runs at once in its caller's task, cancels `heavy`    | — (but see the next row)              |
/// | ffm, mouse move, mouse resize | One ``LatestTaskSlot`` per kind around its session    | A newer event of the same kind        |
/// | AX read of a heavy refresh    | An observe read of ``Platform`` (`AxApp.call`): abandonable | Cancellation of the heavy refresh: it returns at once |
/// | Listing of a heavy refresh    | A deadline per app (``ListingDeadlines``): an app that misses it doesn't answer, and isn't asked again until its listing returns | Cancellation of the heavy refresh before the deadline |
/// | AX read of a command          | A single read of ``Platform`` (`AxApp.run`): awaited  | —                                     |
/// | Placement                     | `AxApp.postPlacements`: a generation per window       | A newer placement, attribute write or close of it |
/// | Native focus (slow path)      | A post with a global generation (`LivePlatform.focus`) | A newer native focus                 |
/// | App registration              | One pending task per pid (`LivePlatform.pendingRegistrations`); a failed one backs off 1–60 s | — |
/// | Order within an app           | FIFO on its actor's thread (posts and awaited calls share one queue): one job per layout: the visible workspaces' placements, then the parks; then focus | — |
///
/// A cancelled heavy refresh stops at its next observe read or at the end of P1, and skips P4. Nothing is queued for
/// retry: the tree is the desired state, and every heavy refresh lays out every window again.
final class Sessions {
    private let heavy = LatestTaskSlot()
    private let mouseFocus = LatestTaskSlot()
    private let mouseMove = LatestTaskSlot()
    private let mouseResize = LatestTaskSlot()

    // MARK: Light sessions and heavy refreshes

    /// Runs `body` as a light session: it cancels the scheduled heavy refresh, takes the native focus
    /// (``Reconcile/syncFocus(isStartup:)``), refreshes the model, runs `body`, refreshes the model again, presents
    /// (``Reconcile/present(nativeFocusBaseline:isLayout:)``) and schedules a heavy refresh. `isStartup`: the light session
    /// of ``startup(_:)``, which registers a new focused window the startup's way
    func light<T>(
        _ event: RefreshSessionEvent,
        _: RunSessionGuard,
        isStartup: Bool = false,
        body: () async throws -> T,
    ) async throws -> T {
        let state = signposter.beginInterval(#function, "event: \(String(describing: event))")
        defer { signposter.endInterval(#function, state) }
        cancelHeavy() // Give priority to the light session
        updateMonitors() // While there are no screens, the commands fail with a message or work on the last monitors
        try await Reconcile.syncFocus(isStartup: isStartup)
        let focusBefore = focus.windowOrNil

        await refreshModel_nonCancellable()
        let result = try await body()
        await refreshModel_nonCancellable()

        try Reconcile.present(nativeFocusBaseline: focusBefore)
        scheduleHeavy(event)
        return result
    }

    /// Focus follows mouse: focuses `window` and changes nothing else. Unlike a light session, it keeps the scheduled heavy
    /// refresh and schedules none (it runs on every mouse move: cancelling would starve the heavy refresh), runs only the
    /// focus callbacks, and doesn't lay out
    func focusFollowsMouse(_ window: Window, _: RunSessionGuard) async throws {
        let state = signposter.beginInterval(#function)
        defer { signposter.endInterval(#function, state) }
        updateMonitors()
        try await Reconcile.syncFocus(isStartup: false)
        // macOS's focus. The model's may differ (e.g. after a click on the desktop): the window gets the native focus
        // unless macOS focuses it already
        let nativeFocus = world.focusStore.lastReadNativeFocusedWindowId.flatMap { Window.get(byId: $0) }
        await checkOnFocusChangedCallbacks_nonCancellable()
        if window.isAlive { _ = window.focusWindow() } // The window may have closed at a suspension point
        await checkOnFocusChangedCallbacks_nonCancellable()
        try Reconcile.present(nativeFocusBaseline: nativeFocus, isLayout: false)
    }

    /// Replaces the scheduled heavy refresh with a new one. `preLayout`: lay out the workspaces before the windows are
    /// re-read too, so that an app activation shows its workspace without waiting for all apps
    func scheduleHeavy(_ event: RefreshSessionEvent, preLayout: Bool = false) {
        heavy.replace {
            try checkCancellation()
            await Reconcile.heavy(event, preLayout: preLayout)
        }
    }

    func cancelHeavy() { heavy.cancel() }

    /// No heavy refresh is scheduled or running (a cancelled one may still run its P3)
    var isHeavyIdle: Bool { heavy.isIdle }

    /// The first sessions after the launch. The heavy refresh registers the windows that are already open, each on the
    /// workspace of its monitor, without moving them. Nothing cancels it, so every window that it finds gets the startup's
    /// on-window-detected callbacks. Then a light session lays them out and runs `body`. The focus callbacks start after it.
    /// The heavy refresh that the light session schedules is an ordinary one (RB-141)
    func startup(_ body: () async throws -> ()) async throws {
        defer { armFocusChangedCallbacks() }
        await Reconcile.heavy(.startup, isStartup: true)
        try await light(.startup, .forceRun, isStartup: true, body: body)
    }

    // MARK: AX notifications

    /// The entry point of the AX observers. On the app's AX thread, the observer callback maps the notification to an
    /// ``AxEvent``, then calls this on the main actor:
    /// `Task.startUnstructured { @MainActor in await world.sessions.onAxEvent(event) }`. It doesn't tell which app's
    /// observer fired: every event except a mouse drag refreshes all apps.
    /// - Ignored while AeroSpace is disabled.
    /// - `.moved` / `.resized` of the window that the user drags or resizes with the mouse: a light session follows the
    ///   mouse (one ``LatestTaskSlot`` per kind). Any other event, e.g. a window that the layout moved: a heavy refresh.
    func onAxEvent(_ event: AxEvent) async {
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

    func onAppHidden() async throws {
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        try await light(.globalObserver(NSWorkspace.didHideApplicationNotification.rawValue), token) {
            unhideMacosHiddenAppsIfConfigured()
        }
    }

    func onLeftMouseUp() async throws {
        // todo reduce number of sessions in the callback
        //  resetManipulatedWithMouseIfPossible might schedule its own heavy refresh
        //  The end of the callback runs a light session or schedules a heavy refresh
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
        mouseFocus.replace { [self] in
            guard let token: RunSessionGuard = .isServerEnabled, let window = try await window(underMouse: location) else { return }
            try await focusFollowsMouse(window, token)
        }
    }

    /// Focus-follows-mouse was turned off: drop the pending focus change
    func cancelFocusFollowsMouse() { mouseFocus.cancel() }
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

/// What started a session: it names the session in the signposts
nonisolated enum RefreshSessionEvent: Sendable {
    case configAutoReload
    case globalObserver(String)
    case globalObserverLeftMouseUp
    case menuBarButton
    case hotkeyBinding
    case startup
    /// An app answered a listing that missed its deadline (``ListingDeadlines``)
    case lateListing
    case socketServer([String])
    case resetManipulatedWithMouse
    case ax(String)
}

/// An AX notification, as an app's AX observer reports it to ``Sessions/onAxEvent(_:)``. It crosses from the app's AX
/// thread to the main actor
nonisolated enum AxEvent: Sendable, Equatable {
    case windowCreated, focusedWindowChanged, destroyed, miniaturized, deminiaturized
    /// kAXMovedNotification, observed on a window: by the user's mouse, by AeroSpace's layout or by the app itself.
    /// The window's id, nil if AX can't tell it (e.g. the window is being destroyed)
    case moved(windowId: WindowId?)
    /// kAXResizedNotification, observed on a window. Same as `moved`
    case resized(windowId: WindowId?)
}
