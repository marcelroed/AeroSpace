import AppKit
import Common

/// The funnel for every session: each input that reads or changes the model enters through one of these methods.
/// - Hotkeys, the CLI server, the menu and config auto-reload call ``light(_:_:body:)``.
/// - GlobalObserver calls ``onWorkspaceNotification(_:)``, ``onAppHidden()`` and ``onLeftMouseUp()``.
/// - The AX observer callbacks call ``onAxEvent(pid:_:)``, the focus-follows-mouse monitor calls ``onMouseMoved(to:)``.
///
/// A light session runs a command-like body between two model refreshes, presents and schedules a heavy refresh. A heavy
/// refresh re-reads the windows of all apps from macOS (it registers new windows and garbage collects closed ones), then
/// presents. Reconcile.swift has their phases.
///
/// How concurrent work coalesces. The code follows this table:
///
/// | Work                          | Mechanism                                             | Preempted by                          |
/// |-------------------------------|-------------------------------------------------------|---------------------------------------|
/// | Heavy refresh                 | `heavy`, a ``LatestTaskSlot``                         | A newer heavy refresh, a light session (but ffm): P1 stops, P3 runs to the end, P4 is skipped |
/// | Light session                 | Runs at once in its caller's task, cancels `heavy` (not ffm's) | — (but see the next row)     |
/// | ffm, mouse move, mouse resize | One ``LatestTaskSlot`` per kind around a light session | A newer event of the same kind       |
/// | AX read of a heavy refresh    | An observe read of ``Platform`` (`AxApp.call`): abandonable | Cancellation of the heavy refresh: it returns at once |
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
    private let focusFollowsMouse = LatestTaskSlot()
    private let mouseMove = LatestTaskSlot()
    private let mouseResize = LatestTaskSlot()

    // MARK: Light sessions and heavy refreshes

    /// Runs `body` as a light session (design-m2.md D4): it cancels the scheduled heavy refresh, takes the native focus
    /// (``Reconcile/syncFocus(isStartup:)``), refreshes the model, runs `body`, refreshes the model again, presents
    /// (``Reconcile/present(nativeFocusBaseline:isTrayDeferred:isLayout:)``) and schedules a heavy refresh.
    ///
    /// Focus follows mouse changes only the focus: it doesn't lay out, and it keeps the scheduled heavy refresh instead of
    /// replacing it. It runs on every mouse move, so cancelling would starve the heavy refresh while the mouse moves
    func light<T>(
        _ event: RefreshSessionEvent,
        _: RunSessionGuard,
        body: () async throws -> T,
    ) async throws -> T {
        let state = signposter.beginInterval(#function, "event: \(event)")
        defer { signposter.endInterval(#function, state) }
        let isFocusFollowsMouse = event.isFocusFollowsMouse
        if !isFocusFollowsMouse { cancelHeavy() } // Give priority to the light session
        updateMonitors() // While there are no screens, the commands fail with a message or work on the last monitors
        try await Reconcile.syncFocus(isStartup: event.isStartup)
        let focusBefore = focus.windowOrNil

        await refreshModel(isFocusFollowsMouse)
        let result = try await body()
        await refreshModel(isFocusFollowsMouse)

        try Reconcile.present(nativeFocusBaseline: focusBefore, isTrayDeferred: true, isLayout: !isFocusFollowsMouse)
        if !isFocusFollowsMouse { scheduleHeavy(event) }
        return result
    }

    /// Focus follows mouse only runs the focus callbacks: it changes nothing else
    private func refreshModel(_ isFocusFollowsMouse: Bool) async {
        if isFocusFollowsMouse {
            await checkOnFocusChangedCallbacks_nonCancellable()
        } else {
            await refreshModel_nonCancellable()
        }
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

    /// The first sessions after the launch. The heavy refresh registers the windows that are already open, each on the
    /// workspace of its monitor, without moving them. Nothing cancels it, so every window that it finds gets the startup's
    /// on-window-detected callbacks. Then a light session lays them out and runs `body`. The focus callbacks start after it
    func startup(_ body: () async throws -> ()) async throws {
        defer { armFocusChangedCallbacks() }
        await Reconcile.heavy(.startup)
        try await light(.startup, .forceRun, body: body)
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

/// What started a session. Sessions pass it explicitly; it also names the session in the signposts
nonisolated enum RefreshSessionEvent: Sendable, CustomStringConvertible {
    case configAutoReload
    case globalObserver(String)
    case globalObserverLeftMouseUp
    case menuBarButton
    case hotkeyBinding
    case startup
    case socketServer([String])
    case resetManipulatedWithMouse
    case ax(String)
    case focusFollowsMouse

    var isStartup: Bool {
        if case .startup = self { return true } else { return false }
    }

    var isFocusFollowsMouse: Bool {
        if case .focusFollowsMouse = self { return true } else { return false }
    }

    var description: String {
        switch self {
            case .ax(let str): "ax(\(str))"
            case .configAutoReload: "configAutoReload"
            case .globalObserver(let str): "globalObserver(\(str))"
            case .globalObserverLeftMouseUp: "globalObserverLeftMouseUp"
            case .hotkeyBinding: "hotkeyBinding"
            case .menuBarButton: "menuBarButton"
            case .resetManipulatedWithMouse: "resetManipulatedWithMouse"
            case .socketServer(let args): "socketServer: \(args.joinArgs())"
            case .startup: "startup"
            case .focusFollowsMouse: "focusFollowsMouse"
        }
    }
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
