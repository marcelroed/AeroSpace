import AppKit
import Common
import Synchronization

/// The macOS ``Platform``. It owns the AX registry: one ``AxApp`` per registered app, each on its own thread. The
/// registration backs off after a failure (RB-113). The termination registry lets a die off the main thread reach the apps
final class LivePlatform: Platform {
    private var apps: [pid_t: LiveApp] = [:]
    /// The app of every window that a read returned, for the calls keyed by window. A registered window also knows its app
    /// (``liveApp(of:)``), so only a window between its read and its registration depends on this map
    private var windowApps: [WindowId: pid_t] = [:]
    /// Registrations in progress. Everyone who asks for the app meanwhile awaits the same task
    private var pendingRegistrations: [pid_t: Task<Void, Never>] = [:]
    /// Internal for tests
    var failedRegistrations: [pid_t: RegistrationBackoff] = [:]
    private var backoffObservers: [any NSObjectProtocol] = []
    /// The registered apps, for a die off the main thread: it can't read `apps`
    nonisolated private let terminationApps: Mutex<[pid_t: AxApp]> = Mutex([:])

    // MARK: Snapshot reads

    func monitors() -> [MonitorInfo] {
        let screens = NSScreen.screens
        guard let mainScreen = screens.singleOrNil(where: \.isMainScreen) ?? screens.first else { return [] }
        let mainMonitorHeight = mainScreen.frame.height
        return screens.enumerated().map {
            $0.element.toMonitorInfo(
                monitorAppKitNsScreenScreensId: $0.offset + 1,
                mainMonitorHeight: mainMonitorHeight,
                isMain: $0.element.isMainScreen,
            )
        }
    }

    /// `monitors()` reads `NSScreen.visibleFrame`, which is slow
    var hasScreens: Bool { !NSScreen.screens.isEmpty }
    func runningApps() -> [AppInfo] { apps.values.map(\.info) }
    func isHidden(_ app: AppInfo) -> Bool { apps[app.pid]?.nsApp.isHidden == true }
    var isLeftMouseDown: Bool { isLeftMouseButtonDown }
    /// Same motivation as in monitorFrameNormalized
    var mouseLocation: CGPoint { NSEvent.mouseLocation.withYAxisFlipped }
    var counters: [String: Int] { axCallCounts.withLock { $0 } }

    // MARK: Observe reads

    func listWindows() async throws(CancellationError) -> [AppInfo: [WindowId]] {
        let frontmostAppBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        for (_, app) in apps { // gc dead apps
            try checkCancellation()
            if app.nsApp.isTerminated {
                destroy(app)
            }
        }
        let alive: [pid_t: [UInt32]]
        do {
            alive = try await withThrowingTaskGroup(of: (pid_t, [UInt32]).self) { group in
                var refreshedPids: Set<pid_t> = []
                func refreshTheApp(_ nsApp: NSRunningApplication) {
                    let pid = nsApp.processIdentifier // Free right after activationPolicy, an XPC after a suspension point
                    refreshedPids.insert(pid)
                    group.addTask { @Sendable @MainActor [self] in
                        guard let app = try await register(nsApp, pid: pid, isBulkScan: true) else { return (pid, []) }
                        return (pid, try await aliveWindowIds(app, frontmostAppBundleId: frontmostAppBundleId))
                    }
                }
                // Register new apps
                for (index, nsApp) in NSWorkspace.shared.runningApplications.enumerated() {
                    // PF-6: each activationPolicy read is a launchservicesd XPC, and there are hundreds of apps.
                    // Yield now and then, so that a light session (`Sessions.light`) can cancel this refresh instead of
                    // waiting for the whole loop
                    if index % 16 == 15 { await Task.yield() }
                    try checkCancellation()
                    if nsApp.activationPolicy == .regular {
                        refreshTheApp(nsApp)
                    }
                }
                for (_, app) in apps where !refreshedPids.contains(app.info.pid) {
                    try checkCancellation()
                    // "About this Mac" window, TouchID, and a lot of other utility windows
                    // We don't monitor them actively as we do for regular apps, but if a window of one of those utility
                    // apps got focused it will end up in `apps`
                    // Don't re-read activationPolicy: after a yield it can disagree with the scan, and an app that became
                    // regular in between would be refreshed by neither loop
                    refreshTheApp(app.nsApp)
                }
                var result: [pid_t: [UInt32]] = [:]
                for try await (pid, windowIds) in group {
                    result[pid] = windowIds
                }
                return result
            }
        } catch {
            throw CancellationError() // The only error of the reads and of the registration
        }
        // A cancelled refresh must not replace the map: a light session may have mapped a new window meanwhile
        try checkCancellation()
        var result: [AppInfo: [WindowId]] = [:]
        var windowApps: [WindowId: pid_t] = [:]
        for (pid, rawIds) in alive {
            guard let app = apps[pid] else { continue }
            let ids = rawIds.map(WindowId.init(raw:))
            result[app.info] = ids
            for id in ids { windowApps[id] = pid }
        }
        self.windowApps = windowApps
        return result
    }

    func focusedWindow() async throws(CancellationError) -> FocusedWindow? {
        guard let nsApp = NSWorkspace.shared.frontmostApplication,
              let app = try await register(nsApp),
              let ax = app.ax,
              let raw = try await ax.call({ app, _ in app.focusedWindowId() })
        else { return nil }
        let id = WindowId(raw: raw)
        windowApps[id] = app.info.pid
        app.lastNativeFocusedWindowId = id
        return FocusedWindow(app: app.info, windowId: id)
    }

    func classify(_ id: WindowId) async throws(CancellationError) -> AxUiElementWindowType? {
        guard let app = liveApp(of: id) else { return nil }
        return try await observe(id) { [classifier = app.classifier(getWindowLevel(for: id))] in classifier.windowType($0, $1) }
    }

    func nativeFacts(_ id: WindowId) async throws(CancellationError) -> NativeFacts? {
        try await observe(id) { app, raw in app.nativeFacts(raw) }
    }

    func observedRect(_ id: WindowId) async throws(CancellationError) -> Rect? {
        try await observe(id) { app, raw in app.rect(raw) }
    }

    // MARK: Single reads

    func rect(_ id: WindowId) async -> Rect? {
        await read(id) { app, raw in app.rect(raw) }
    }

    func title(_ id: WindowId) async -> String? {
        await read(id) { app, raw in app.window(raw)?.get(Ax.titleAttr) }
    }

    func facts(_ id: WindowId) async -> NativeFacts? {
        await read(id) { app, raw in app.nativeFacts(raw) }
    }

    func kind(_ id: WindowId) async -> AxUiElementWindowType? {
        guard let app = liveApp(of: id) else { return nil }
        return await read(id) { [classifier = app.classifier(getWindowLevel(for: id))] in classifier.windowType($0, $1) }
    }

    func windowCount(_ app: AppInfo) async -> Int? {
        guard let ax = apps[app.pid]?.ax else { return nil }
        return await ax.run { $0.element.get(Ax.windowsAttr)?.count }
    }

    func debugInfo(_ id: WindowId) async -> WindowDebugInfo? {
        guard let app = liveApp(of: id), let ax = app.ax else { return nil }
        let nsApp = app.nsApp
        let appInfoDic: [String: Any] = nsApp.bundleURL.flatMap { Bundle(url: $0) }?.infoDictionary ?? [:]
        let windowLevel = getWindowLevel(for: id)
        let classifier = app.classifier(windowLevel)
        let raw = id.raw
        let dump: (window: OrderedJson.JsonDict, app: OrderedJson.JsonDict, isDialog: Bool, isWindow: Bool)? = await ax.run { app in
            guard let window = app.window(raw) else { return nil }
            return (
                dumpAxRecursive(window, .window),
                dumpAxRecursive(app.element, .app),
                window.isDialogHeuristic(classifier.appId, windowLevel),
                window.isWindowHeuristic(axApp: app.element, classifier.appId, classifier.nsApp.activationPolicy, windowLevel),
            )
        }
        guard let dump else { return nil }
        return WindowDebugInfo(
            axWindow: dump.window,
            axApp: dump.app,
            windowLevel: windowLevel,
            appVersionShort: appInfoDic["CFBundleShortVersionString"] as? String,
            appVersion: appInfoDic["CFBundleVersion"] as? String,
            activationPolicy: nsApp.activationPolicy.prettyDescription,
            execUrl: nsApp.executableURL?.description,
            bundleUrl: nsApp.bundleURL?.description,
            isDialog: dump.isDialog,
            isWindow: dump.isWindow,
        )
    }

    // MARK: Effects

    func apply(_ batch: [Placement]) {
        for placement in batch {
            switch placement {
                case .frame(let id, let topLeft, let size):
                    guard let ax = liveApp(of: id)?.ax else { continue }
                    let raw = id.raw
                    ax.postWindowWrite(raw) { app, isLatest in app.place(raw, topLeft, size, isLatest) }
                case .park(let id, let target):
                    guard let app = liveApp(of: id), let ax = app.ax else { continue }
                    let raw = id.raw
                    let corner = ParkCorner(target, isZoom: app.appId == .zoom)
                    ax.postWindowWrite(raw) { app, isLatest in app.park(raw, corner, isLatest) }
            }
        }
    }

    func focus(_ id: WindowId) {
        if serverArgs.isReadOnly { return }
        // Bump first: a focus posted earlier for another window must not run, even if this window's app is gone
        let generation = nativeFocusGeneration.wrappingAdd(1, ordering: .sequentiallyConsistent).newValue
        guard let app = liveApp(of: id) else { return }
        // Performance optimization. If possible avoid doing AX requests
        // (important for apps which are slow at responding even such basic AX requests. E.g. Godot)
        // Beware of the macOS bug: https://github.com/nikitabobko/AeroSpace/issues/101
        if (!NSScreen.screensHaveSeparateSpaces || world.monitors.all.count == 1) &&
            (app.lastNativeFocusedWindowId == id || app.windowsCount == 1)
        {
            app.nsApp.activateForNativeFocus()
        } else {
            let raw = id.raw
            app.ax?.post { [nsApp = app.nsApp] app in
                if nativeFocusGeneration.load(ordering: .sequentiallyConsistent) == generation {
                    app.focus(raw, nsApp)
                }
            }
        }
    }

    func close(_ id: WindowId) {
        if serverArgs.isReadOnly { return }
        let raw = id.raw
        liveApp(of: id)?.ax?.postWindowWrite(raw) { app, _ in app.close(raw) }
    }

    /// Cancels a pending placement of the window, never the reverse
    func setNative(_ id: WindowId, _ change: NativeChange) {
        let raw = id.raw
        liveApp(of: id)?.ax?.postWindowWrite(raw) { app, _ in
            switch change {
                case .fullscreen(let value): app.window(raw)?.set(Ax.isFullscreenAttr, value)
                case .minimized(let value): app.window(raw)?.set(Ax.minimizedAttr, value)
            }
        }
    }

    func unhideApp(_ app: AppInfo) {
        apps[app.pid]?.nsApp.unhide()
    }

    func quit(_ app: AppInfo) -> Bool {
        apps[app.pid]?.nsApp.terminate() == true
    }

    // MARK: Termination

    nonisolated func restoreForTermination() {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                restoreWindowsOnMainThread(world.windows.values.compactMap { window in
                    // The restore may run when something went wrong (e.g. some windows are unbound). That's why it
                    // doesn't read `.parent`
                    liveApp(of: window.windowId)?.ax.map { (app: $0, windowId: window.windowId.raw, window.lastFloatingSize) }
                })
            }
        } else {
            restoreWindowsOffMainThread(terminationApps.withLock { Array($0.values) })
        }
    }

    // MARK: The registry

    private func liveApp(of id: WindowId) -> LiveApp? {
        (windowApps[id] ?? world.windows[id]?.app.pid).flatMap { apps[$0] }
    }

    /// - `isBulkScan`: the refresh's scan of all apps. It skips an app whose registration failed recently (RB-113). A
    ///   single lookup (the frontmost app) always tries again: a just-launched app's focused window must not read as nil
    private func register(_ nsApp: NSRunningApplication, pid: pid_t? = nil, isBulkScan: Bool = false) async throws(CancellationError) -> LiveApp? {
        let pid = pid ?? nsApp.processIdentifier
        // Look up first (saves a bundleIdentifier XPC): the lock screen and AeroSpace itself are never registered
        if let existing = apps[pid] { return existing }
        // Don't perceive any of the lock screen windows as real windows
        // Otherwise, false positive ax notifications might trigger that lead to gcWindows
        if nsApp.bundleIdentifier == lockScreenAppBundleId { return nil }
        // AX requests crash if you send them to yourself
        if pid == myPid { return nil }

        try checkCancellation()
        guard let registration = pendingRegistrations[pid] ?? startRegistration(nsApp, pid, isBulkScan) else { return nil }
        await registration.value // Not abandonable: it waits for the app's subscription
        try checkCancellation()
        return apps[pid]
    }

    /// nil for the bulk scan while a failed registration of the app backs off (RB-113)
    private func startRegistration(_ nsApp: NSRunningApplication, _ pid: pid_t, _ isBulkScan: Bool) -> Task<Void, Never>? {
        if isBulkScan, let backoff = failedRegistrations[pid], ContinuousClock.now < backoff.retryAt { return nil }
        let threadName = "AxAppThread \(nsApp.idForDebug)"
        let registration = Task.startUnstructured { @MainActor [self] in
            let ax = AxApp(pid: pid, threadName: threadName)
            let isSubscribed = await ax.subscribe()
            pendingRegistrations[pid] = nil
            if isSubscribed {
                failedRegistrations[pid] = nil
                apps[pid] = LiveApp(nsApp, ax)
                terminationApps.withLock { $0[pid] = ax }
            } else { // `ax` deinits: its thread exits
                failedRegistrations[pid] = RegistrationBackoff(after: failedRegistrations[pid], now: .now)
                forgetFailedRegistrationsOnLaunchAndActivation()
            }
        }
        pendingRegistrations[pid] = registration
        return registration
    }

    /// Launching, activating or terminating an app forgets its failed registrations (RB-113)
    private func forgetFailedRegistrationsOnLaunchAndActivation() {
        if !backoffObservers.isEmpty { return }
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        backoffObservers = names.map { name in
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] in
                self?.forgetFailedRegistration($0)
            }
        }
    }

    /// Internal for tests
    nonisolated func forgetFailedRegistration(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        MainActor.assumeIsolated { // The observers' queue is .main
            _ = failedRegistrations.removeValue(forKey: pid)
        }
    }

    private func aliveWindowIds(_ app: LiveApp, frontmostAppBundleId: String?) async throws(CancellationError) -> [UInt32] {
        if app.nsApp.isTerminated {
            destroy(app)
            return []
        }
        guard let ax = app.ax else { return [] }
        let isLockScreen = frontmostAppBundleId == lockScreenAppBundleId
        let alive = try await ax.call { app, isAbandoned in app.refreshWindows(isLockScreen: isLockScreen, isAbandoned) }
        app.windowsCount = alive.count
        return alive
    }

    private func destroy(_ app: LiveApp) {
        let pid = app.info.pid
        apps.removeValue(forKey: pid)
        windowApps = windowApps.filter { $0.value != pid }
        terminationApps.withLock { _ = $0.removeValue(forKey: pid) }
        app.ax = nil
    }

    /// An abandonable read of the window's app, see ``AxApp/call(_:)``. nil if the app is gone
    private func observe<T: Sendable>(
        _ id: WindowId,
        _ body: @escaping @Sendable (isolated AxApp, UInt32) -> T?,
    ) async throws(CancellationError) -> T? {
        guard let ax = liveApp(of: id)?.ax else { return nil }
        let raw = id.raw
        return try await ax.call { app, _ in body(app, raw) }
    }

    /// A read of the window's app that waits for it, see ``AxApp/run(_:)``. nil if the app is gone
    private func read<T: Sendable>(_ id: WindowId, _ body: @escaping @Sendable (isolated AxApp, UInt32) -> T?) async -> T? {
        guard let ax = liveApp(of: id)?.ax else { return nil }
        let raw = id.raw
        return await ax.run { app in body(app, raw) }
    }
}

/// The latest-wins slot of the native focus's slow path: a newer focus request makes a pending one stale
nonisolated private let nativeFocusGeneration: Atomic<UInt64> = Atomic(0)

/// A registered app, main's side. Its AX state and calls live in ``AxApp``, on the app's own thread
private final class LiveApp {
    let info: AppInfo
    let appId: KnownBundleId?
    let nsApp: NSRunningApplication
    /// nil once the app is destroyed: later calls do nothing. The actor then deinits on its thread after its last job
    var ax: AxApp?
    /// Main's mirror for the native focus fast path (#101), updated by each refresh
    var windowsCount = 0
    var lastNativeFocusedWindowId: WindowId? = nil

    init(_ nsApp: NSRunningApplication, _ ax: AxApp) {
        self.nsApp = nsApp
        self.ax = ax
        info = AppInfo(
            pid: nsApp.processIdentifier,
            bundleId: nsApp.bundleIdentifier,
            name: nsApp.localizedName,
            execPath: nsApp.executableURL?.path,
            bundlePath: nsApp.bundleURL?.path,
        )
        appId = nsApp.bundleIdentifier.flatMap { KnownBundleId.init(rawValue: $0) }
    }

    /// What the window classifier needs from main, captured for the app's thread
    func classifier(_ windowLevel: MacOsWindowLevel?) -> WindowClassifier {
        WindowClassifier(appId: appId, nsApp: nsApp, windowLevel: windowLevel)
    }
}

/// Where ``AxApp/park(_:_:_:)`` puts a window: computed on main, but for the window's width, which the app's thread reads
nonisolated struct ParkCorner: Sendable {
    /// The bottom left corner, offset. The window goes left of it. nil: the bottom right corner
    let bottomLeft: CGPoint?
    let bottomRight: CGPoint
}

extension ParkCorner {
    init(_ target: ParkTarget, isZoom: Bool) {
        // Zoom will jump off if you do one pixel offset https://github.com/nikitabobko/AeroSpace/issues/527
        // todo this ad hoc won't be necessary once I implement optimization suggested by Zalim
        let rect = target.visibleRect
        bottomLeft = target.corner == .bottomLeftCorner ? rect.bottomLeftCorner + (isZoom ? .zero : CGPoint(x: 1, y: -1)) : nil
        bottomRight = rect.bottomRightCorner - (isZoom ? .zero : CGPoint(x: 1, y: 1))
    }
}

nonisolated private struct WindowClassifier: Sendable {
    let appId: KnownBundleId?
    /// Its activationPolicy is an XPC: read it on the app's thread
    let nsApp: NSRunningApplication
    let windowLevel: MacOsWindowLevel?

    func windowType(_ app: isolated AxApp, _ windowId: UInt32) -> AxUiElementWindowType? {
        app.window(windowId)?.getWindowType(axApp: app.element, appId, nsApp.activationPolicy, windowLevel)
    }
}

/// RB-113: after an app's AX subscription fails, the refresh's bulk scan retries its registration after 1 s, then 2 s,
/// 4 s, … up to 60 s, instead of on every refresh. Launching, activating or terminating the app forgets the failures
nonisolated struct RegistrationBackoff: Equatable {
    let delay: Duration
    let retryAt: ContinuousClock.Instant

    init(after previous: RegistrationBackoff?, now: ContinuousClock.Instant) {
        delay = previous.map { min($0.delay * 2, .seconds(60)) } ?? .seconds(1)
        retryAt = now + delay
    }
}

// Note to myself: Don't use NSScreen.main, it's garbage
// 1. The name is misleading, it's supposed to be called "focusedScreen"
// 2. It's inaccurate because NSScreen.main doesn't work correctly from NSWorkspace.didActivateApplicationNotification &
//    kAXFocusedWindowChangedNotification callbacks.
extension NSScreen {
    /// ``frame`` and ``visibleFrame`` are crazy: (0, 0) is the main screen's bottom left corner, and the positive
    /// y-axis goes up. ``MonitorInfo`` normalizes them to AX's coordinates: (0, 0) is the main screen's top left corner,
    /// and the positive y-axis goes down
    fileprivate func toMonitorInfo(monitorAppKitNsScreenScreensId: Int, mainMonitorHeight: CGFloat, isMain: Bool) -> MonitorInfo {
        MonitorInfo(
            monitorAppKitNsScreenScreensId: monitorAppKitNsScreenScreensId,
            name: localizedName,
            rect: frame.monitorFrameNormalized(mainMonitorHeight: mainMonitorHeight),
            visibleRect: visibleFrame.monitorFrameNormalized(mainMonitorHeight: mainMonitorHeight),
            isMain: isMain,
        )
    }

    fileprivate var isMainScreen: Bool {
        frame.minX == 0 && frame.minY == 0
    }
}
