import AppKit
import Common

/// The phased reconcile: how a session brings the tree and macOS together. A heavy refresh runs five
/// phases:
/// - P0 begin (sync): skip while disabled or without screens; take the snapshot of the monitors.
/// - P1 observe (async, abandonable): read macOS. No tree writes: a cancelled refresh leaves the model as it was.
/// - P2 commit (sync): write what P1 read into the tree, then tidy it. No await: no other session runs in the middle
///   of it.
/// - P3 callbacks (async, shielded): the focus callbacks of P2's focus change, then on-window-detected for the new
///   windows. Cancelling the refresh doesn't cancel them, so no new window misses its callbacks.
/// - P4 present (sync): one placement batch for every window, then the native focus, then the tray. A cancelled refresh
///   skips it: the light session that cancelled it presents.
///
/// Cancellation is checked at the end of P1 and at the start of P4 only. Nothing is queued for retry: what a refresh
/// skips, the next one does again, because each one recomputes everything from the tree and from macOS.
enum Reconcile {
    /// The heavy refresh of ``Sessions``. `preLayout`: present before P1 too, so that an app activation shows the app's
    /// workspace without waiting for the windows of all apps. `isStartup`: ``Sessions/startup(_:)``'s own heavy refresh. It
    /// waits for every app, registers every window on the workspace of the monitor that the window is on, and doesn't
    /// present: the startup's light session does
    static func heavy(_ event: RefreshSessionEvent, preLayout: Bool = false, isStartup: Bool = false) async {
        let state = signposter.beginInterval(#function, "event: \(String(describing: event))")
        defer { signposter.endInterval(#function, state) }
        // P0. No screens (e.g., during display reconfiguration): nothing can be laid out. The first session after the
        // screens come back catches up
        if !world.isEnabled || !updateMonitors() { return }
        do {
            if preLayout {
                if let focused = try await readNativeFocus(), let window = Window.get(byId: focused.windowId) {
                    syncFocusFromMacOs(window)
                }
                try present(nativeFocusBaseline: focus.windowOrNil)
            }
            guard let observation = try await observe(isStartup: isStartup) else { return } // P1
            let committed = commit(observation, isStartup: isStartup) // P2
            // P3. A task that the refresh's cancellation doesn't reach
            let nativeFocusBaseline = await Task.immediate { @MainActor in await runCallbacks(committed, isStartup: isStartup) }.value
            if isStartup { return }
            // P3's callbacks may have changed the tree after the session that cancelled this refresh presented.
            // A heavy refresh that is scheduled or running presents anyway
            if Task.isCancelled && committed.hasCallbacks && world.sessions.isHeavyIdle { world.sessions.scheduleHeavy(event) }
            // No await after this: until the heavy slot is idle, Sessions leaves the moves of known windows to P4
            try present(nativeFocusBaseline: nativeFocusBaseline) // P4
        } catch {
            // Cancelled by a newer heavy refresh or by a light session. Only P1 and P4 stop: the tree is as P2 left it
        }
    }

    /// The light session's observe and commit: takes the native focus from macOS. A new focused window is registered (and
    /// recorded by debug-windows), its on-window-detected callbacks run (as in P3), then it takes the focus
    static func syncFocus(isStartup: Bool) async throws(CancellationError) {
        guard let focused = try await readNativeFocus() else { return syncFocusFromMacOs(nil) }
        if let window = Window.get(byId: focused.windowId) { return syncFocusFromMacOs(window) }
        // The read is stale once another session reads another native focus at a suspension point below, even one that
        // the model has already: the newest read wins
        func isNativeFocusCurrent() -> Bool { world.focusStore.lastReadNativeFocusedWindowId == focused.windowId }
        let detected = try await world.platform.classify([focused.app: [focused.windowId]])[focused.windowId]
        let debugInfos = detected == nil ? [] : try await readDebugInfos(focused, [])
        if !isNativeFocusCurrent() { return } // The heavy refresh registers the window
        // Another session may have registered the window at the suspension points above
        if let window = Window.get(byId: focused.windowId) { return syncFocusFromMacOs(window) }
        guard let detected else { return } // The window closed, or its kind is unknown: the heavy refresh tries again
        let window = registerWindow(focused.windowId, focused.app, detected, isStartup: isStartup)
        await recordDebugWindows(debugInfos)
        if restoreClosedWindowsCacheIfNeeded(newWindows: [window]).isEmpty {
            await runOnWindowDetected(ifConventional: window, isStartup: isStartup)
        }
        if window.isAlive && isNativeFocusCurrent() { syncFocusFromMacOs(window) }
    }

    // MARK: P1 observe

    /// What P1 read. P2 commits it without another read
    struct Observation {
        /// The window with the native focus
        let focused: FocusedWindow?
        let apps: [AppWindows]
        /// The windows that were registered when P1 started. The GC drops only these: the listing doesn't know a window
        /// that another session registered meanwhile
        let known: Set<WindowId>
        /// The new windows (listed, or focused, and not registered), in listing order, with their apps
        let new: [(id: WindowId, app: AppInfo)]
        /// The kind and the frame of each new window, of each popup and of each window whose macOS state hid its kind.
        /// A window that is missing is gone, or its kind is unknown while it's off-screen
        let detected: [WindowId: DetectedWindow]
        /// The native states of the bound windows that their apps listed, new ones included. A window that is missing
        /// keeps its state
        let facts: [WindowId: NativeFacts]
        /// While debug-windows records: the dumps of the focused window and of the new ones that it doesn't have yet
        let debugInfos: [(id: WindowId, info: WindowDebugInfo)]
    }

    /// P1. Abandonable: every read throws once the refresh is cancelled, and a hung app's windows aren't read: its listing
    /// has a deadline, but at startup. nil if the screens disappeared meanwhile
    static func observe(isStartup: Bool = false) async throws(CancellationError) -> Observation? {
        let platform = world.platform
        let known = Set(world.windows.keys)
        let focused = try await readNativeFocus()
        let apps = try await platform.listWindows(waitingForEveryApp: isStartup)

        var new: [(id: WindowId, app: AppInfo)] = []
        var listed: Set<WindowId> = []
        for case .listed(let app, let ids) in apps {
            listed.formUnion(ids)
            new += ids.filter { world.windows[$0] == nil }.map { (id: $0, app: app) }
        }
        // A window that its app doesn't list (e.g. of an app that isn't regular) is still registered when it's focused
        if let focused, world.windows[focused.windowId] == nil, !listed.contains(focused.windowId) {
            new.append((id: focused.windowId, app: focused.app))
        }

        var toClassify: [AppInfo: [WindowId]] = [:]
        for (id, app) in new { toClassify[app, default: []].append(id) }
        for case let popup as Window in macosPopupWindowsContainer.children where listed.contains(popup.windowId) {
            toClassify[popup.app, default: []].append(popup.windowId)
        }
        let boundListed = boundNonPopupWindows.filter { listed.contains($0.windowId) }
        for window in boundListed where window.layoutReason.hidesKind {
            toClassify[window.app, default: []].append(window.windowId)
        }
        let detected = try await platform.classify(toClassify)
        // A new window that classify didn't detect (gone, or off-screen with a kind that depends on its level) isn't
        // registered in P2: its states and its dump would go unused. E.g. a minimized Chrome window stays unregistered
        // for as long as it's minimized, and every heavy refresh would read them again
        let registrable = new.filter { detected[$0.id] != nil }
        var toRead: [AppInfo: [WindowId]] = [:]
        for (id, app) in registrable { toRead[app, default: []].append(id) }
        for window in boundListed { toRead[window.app, default: []].append(window.windowId) }
        let facts = try await platform.nativeFacts(toRead)
        let isFocusedRegistrable = focused.map { world.windows[$0.windowId] != nil || detected[$0.windowId] != nil } == true
        let debugInfos = try await readDebugInfos(isFocusedRegistrable ? focused : nil, registrable)

        try checkCancellation()
        // RB-01: the screens may disappear during the reads (e.g. display reconfiguration on wake). Leave the windows to
        // a session that runs with screens
        if !platform.hasScreens { return nil }
        return Observation(
            focused: focused, apps: apps, known: known, new: new, detected: detected, facts: facts, debugInfos: debugInfos,
        )
    }

    /// Every session reads the native focus through this: P3 and ``syncFocus(isStartup:)`` tell a stale read by it
    private static func readNativeFocus() async throws(CancellationError) -> FocusedWindow? {
        let focused = try await world.platform.focusedWindow()
        world.focusStore.lastReadNativeFocusedWindowId = focused?.windowId
        return focused
    }

    /// Abandonable like the other reads of P1: a hung app doesn't hold the sessions while debug-windows records
    private static func readDebugInfos(
        _ focused: FocusedWindow?,
        _ new: [(id: WindowId, app: AppInfo)],
    ) async throws(CancellationError) -> [(id: WindowId, info: WindowDebugInfo)] {
        guard case .recording(let log) = world.debugWindows else { return [] }
        var order: [(id: WindowId, app: AppInfo)] = focused.map { [(id: $0.windowId, app: $0.app)] } ?? []
        order += new.filter { $0.id != focused?.windowId }
        order = order.filter { log.dumps[$0.id] == nil }
        if order.isEmpty { return [] }
        var windows: [AppInfo: [WindowId]] = [:]
        for (id, app) in order { windows[app, default: []].append(id) }
        let infos = try await world.platform.debugInfos(windows)
        return order.compactMap { window in infos[window.id].map { (id: window.id, info: $0) } }
    }

    // MARK: P2 commit

    /// What P2 leaves for P3 and P4
    struct Committed {
        /// The windows whose on-window-detected callbacks run in P3, in order: the new ones in listing order (those that
        /// the closed-windows cache placed excluded), then the former popups
        let detected: [WindowId]
        /// The focused window if it's new: it takes the focus in P3, after its callbacks, unless another session read
        /// another native focus meanwhile: `lastReadNativeFocusedWindowId` isn't it anymore
        let newFocusedWindow: WindowId?
        /// The focus change that the focus sync made, recorded before the GC (#1089). Its callbacks run first in P3
        let focusChange: RecordedFocusChange?
        /// The focus as macOS sees it after P2 (the GC's refocus rule gives the native focus itself)
        let nativeFocusBaseline: Window?
        let debugInfos: [(id: WindowId, info: WindowDebugInfo)]

        /// P3 runs callbacks whose commands may change the tree
        var hasCallbacks: Bool { !detected.isEmpty || newFocusedWindow != nil || focusChange != nil }
    }

    /// P2. Sync: nothing else changes the tree meanwhile, and the objects it resolves stay valid until it returns
    static func commit(_ o: Observation, isStartup: Bool) -> Committed {
        // 1. The focus from macOS. A new focused window takes it in P3
        let newFocusedWindow = o.focused.map(\.windowId).flatMap { Window.get(byId: $0) == nil ? $0 : nil }
        if newFocusedWindow == nil { syncFocusFromMacOs(o.focused.flatMap { Window.get(byId: $0.windowId) }) }
        // The GC's refocus rule needs the workspace that the focus just left (#1089)
        let focusChange = recordFocusChange()

        // 2. GC, only on positive evidence: the app terminated (it's missing from the listing), or it answered without
        // the window. A window of an app that didn't answer stays. The closed-windows cache is captured before the
        // first window goes. The refocus rule (#65, #201, #1089) runs in the GC of each window
        var listed: Set<WindowId> = []
        var noAnswer: Set<pid_t> = []
        for app in o.apps {
            switch app {
                case .listed(_, let ids): listed.formUnion(ids)
                case .noAnswer(let app): noAnswer.insert(app.pid)
            }
        }
        for id in o.known.filter({ !listed.contains($0) }).sorted() {
            guard let window = Window.get(byId: id), !noAnswer.contains(window.app.pid) else { continue }
            window.garbageCollect(skipClosedWindowsCache: false)
        }

        // 3. Register the new windows in listing order. A window that is unclassified (gone, or off-screen with a kind
        // that depends on its level) or that another session registered meanwhile is skipped. The next refresh
        // tries again
        var newWindows: [Window] = []
        for (id, app) in o.new {
            guard let detected = o.detected[id], Window.get(byId: id) == nil else { continue }
            newWindows.append(registerWindow(id, app, detected, isStartup: isStartup))
        }

        // 4. The closed-windows cache places the windows it knows: they skip on-window-detected
        let restored = restoreClosedWindowsCacheIfNeeded(newWindows: newWindows)
        var detected: [WindowId] = newWindows.map(\.windowId).filter { !restored.contains($0) }

        // 5. The macOS states: fullscreen, minimized, hidden app
        normalizeLayoutReason(o.facts, o.detected)

        // 6. A popup that isn't one anymore (e.g. a tab dragged out of a browser window) goes where its kind goes. Only an
        // on-screen read can tell that: an off-screen popup (e.g. picture in picture while its app is hidden) stays one
        for case let popup as Window in macosPopupWindowsContainer.children {
            guard let kind = o.detected[popup.windowId]?.kindOnScreen, kind != .popup else { continue }
            popup.relayoutWindow(on: focus.workspace, as: kind)
            detected.append(popup.windowId)
        }

        // 7. The workspace GC comes after the windows', because the workspaces contain them
        tidyModel()
        return Committed(
            detected: detected,
            newFocusedWindow: newFocusedWindow,
            focusChange: focusChange,
            nativeFocusBaseline: focus.windowOrNil,
            debugInfos: o.debugInfos,
        )
    }

    // MARK: P3 callbacks

    /// P3. Shielded: it runs to the end even if the refresh is cancelled. Each window is resolved again: a callback may
    /// close another one. Returns the focus as macOS sees it: P4 gives the native focus if the focus differs from it then
    private static func runCallbacks(_ c: Committed, isStartup: Bool) async -> Window? {
        // First, before any suspension point: a newer focus change's callbacks can't run before them
        if let change = c.focusChange { await runFocusChangedCallbacks(change) }
        await recordDebugWindows(c.debugInfos)
        for id in c.detected {
            guard let window = Window.get(byId: id) else { continue }
            await runOnWindowDetected(ifConventional: window, isStartup: isStartup)
        }
        var nativeFocusBaseline = c.nativeFocusBaseline
        if let id = c.newFocusedWindow, let window = Window.get(byId: id), world.focusStore.lastReadNativeFocusedWindowId == id {
            syncFocusFromMacOs(window)
            nativeFocusBaseline = focus.windowOrNil
        }
        await refreshModel_nonCancellable() // The focus changes since P2
        return nativeFocusBaseline
    }

    /// The dumps that P1 or the light session read, of the windows that are still registered
    private static func recordDebugWindows(_ infos: [(id: WindowId, info: WindowDebugInfo)]) async {
        for (id, info) in infos {
            guard let window = Window.get(byId: id) else { continue }
            await recordDebugWindow(id) { await dumpWindowDebugInfo(window, info) }
        }
    }

    // MARK: P4 present

    /// P4: the layout of every workspace with the native focus if the focus differs from `nativeFocusBaseline`, then the
    /// tray. A cancelled session presents nothing. `isLayout` false: focus-follows-mouse doesn't lay out
    static func present(nativeFocusBaseline: Window?, isLayout: Bool = true) throws(CancellationError) {
        try checkCancellation()
        let batch: [Placement] = isLayout ? placements() : []
        let focused = focus.windowOrNil
        world.platform.apply(batch, focus: focused == nativeFocusBaseline ? nil : focused?.windowId)
        updateTrayText()
        world.ui.refreshSecureInputPanel()
    }
}

/// The model refresh of the light session, of each command and of P3's end: tidies the model, then runs the focus
/// callbacks, which see the tidy tree. Their commands refresh the model again
func refreshModel_nonCancellable() async {
    tidyModel()
    await checkOnFocusChangedCallbacks_nonCancellable()
}

/// The workspace GC, then the normalization of the containers of every workspace: not only of the visible ones, because
/// most commands take --window-id and --workspace
func tidyModel() {
    Workspace.garbageCollectUnusedWorkspaces()
    for workspace in Workspace.all {
        workspace.normalizeContainers()
    }
}

/// The windows on the workspaces and the minimized ones
private var boundNonPopupWindows: [Window] {
    Workspace.all.flatMap(\.allLeafWindowsRecursive) + macosMinimizedWindowsContainer.children.filterIsInstance(of: Window.self)
}
