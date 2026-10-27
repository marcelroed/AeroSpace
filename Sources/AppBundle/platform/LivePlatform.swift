import AppKit
import Carbon
import Common
import Synchronization

/// The macOS ``Platform``. It owns the AX registry: one ``AxApp`` per registered app, each on its own thread. The
/// registration backs off after a failure (RB-113). The termination registry lets a die off the main thread reach the apps
final class LivePlatform: Platform {
    private var apps: [pid_t: LiveApp] = [:]
    /// Registrations in progress. Everyone who asks for the app meanwhile awaits the same task
    private var pendingRegistrations: [pid_t: Task<Void, Never>] = [:]
    /// Internal for tests
    var failedRegistrations: [pid_t: RegistrationBackoff] = [:]
    private var backoffObservers: [any NSObjectProtocol] = []
    private let listingDeadlines = ListingDeadlines(minDeadline: .milliseconds(250), maxDeadline: .seconds(1))
    /// The registered apps, for a die off the main thread: it can't read `apps`
    nonisolated private let terminationApps: Mutex<[pid_t: AxApp]> = Mutex([:])
    /// The last monitors with screens, see ``monitors()``. nil before the first: then nothing is parked
    nonisolated private let terminationMonitors: Mutex<TerminationMonitors?> = Mutex(nil)

    // MARK: Snapshot reads

    /// Every session's snapshot (``updateMonitors(_:)``). It also publishes the monitors for termination
    func monitors() -> [MonitorInfo] {
        let screens = NSScreen.screens
        guard let mainScreen = screens.singleOrNil(where: \.isMainScreen) ?? screens.first else { return [] }
        let mainMonitorHeight = mainScreen.frame.height
        let monitors = screens.enumerated().map {
            $0.element.toMonitorInfo(
                monitorAppKitNsScreenScreensId: $0.offset + 1,
                mainMonitorHeight: mainMonitorHeight,
                isMain: $0.element.isMainScreen,
            )
        }
        if let snapshot = Monitors(monitors) {
            terminationMonitors.withLock { $0 = TerminationMonitors(all: snapshot.all, main: snapshot.main) }
        }
        return monitors
    }

    /// `monitors()` reads `NSScreen.visibleFrame`, which is slow
    var hasScreens: Bool { !NSScreen.screens.isEmpty }
    func runningApps() -> [AppInfo] { apps.values.map(\.info) }
    func isHidden(_ app: AppInfo) -> Bool { apps[app.pid]?.nsApp.isHidden == true }
    var isLeftMouseDown: Bool { isLeftMouseButtonDown }
    /// AppKit's y axis goes up from the main monitor's bottom, AX's goes down from its top
    var mouseLocation: CGPoint { NSEvent.mouseLocation.withYAxisFlipped }
    var isSecureInputEnabled: Bool { IsSecureEventInputEnabled() }
    var counters: [String: Int] { axCallCounts.withLock { $0 } }

    // MARK: Observe reads

    func listWindows(waitingForEveryApp: Bool) async throws(CancellationError) -> [AppWindows] {
        let frontmostAppBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        for (_, app) in apps { // gc dead apps
            try checkCancellation()
            if app.nsApp.isTerminated {
                destroy(app)
            }
        }
        let scanOrder: [pid_t]
        let alive: [pid_t: [UInt32]?]
        do {
            (scanOrder, alive) = try await withThrowingTaskGroup(of: (pid_t, [UInt32]?).self) { group in
                var refreshedPids: Set<pid_t> = []
                var scanOrder: [pid_t] = []
                func refreshTheApp(_ nsApp: NSRunningApplication) {
                    let pid = nsApp.processIdentifier // Free right after activationPolicy, an XPC after a suspension point
                    refreshedPids.insert(pid)
                    scanOrder.append(pid)
                    group.addTask { @Sendable @MainActor [self] in
                        let windowIds = try await listingDeadlines.list(pid, hasDeadline: !waitingForEveryApp) {
                            [self] () async throws(CancellationError) -> [UInt32]? in
                            guard let app = try await register(nsApp, pid: pid, isBulkScan: true) else { return [] }
                            return try await aliveWindowIds(app, frontmostAppBundleId: frontmostAppBundleId)
                        }
                        return (pid, windowIds)
                    }
                }
                for (index, nsApp) in NSWorkspace.shared.runningApplications.enumerated() {
                    // Each activationPolicy read is a launchservicesd XPC, and there are hundreds of apps.
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
                var result: [pid_t: [UInt32]?] = [:]
                for try await (pid, windowIds) in group {
                    result[pid] = windowIds
                }
                return (scanOrder, result)
            }
        } catch {
            throw CancellationError() // The only error of the reads and of the registration
        }
        var result: [AppWindows] = []
        for pid in scanOrder { // The order of NSWorkspace's apps: a new window's order doesn't depend on the apps' answers
            guard let app = apps[pid], let answer = alive[pid] else { continue } // Not registered, or terminated meanwhile
            guard let rawIds = answer else {
                result.append(.noAnswer(app.info))
                continue
            }
            result.append(.listed(app.info, rawIds.map(WindowId.init(raw:))))
        }
        return result
    }

    func focusedWindow() async throws(CancellationError) -> FocusedWindow? {
        guard let nsApp = NSWorkspace.shared.frontmostApplication,
              let app = try await register(nsApp),
              let ax = app.ax,
              let raw = try await ax.call({ app, _ in app.focusedWindowId() })
        else { return nil }
        let id = WindowId(raw: raw)
        app.lastNativeFocusedWindowId = id
        return FocusedWindow(app: app.info, windowId: id)
    }

    func classify(_ windows: [AppInfo: [WindowId]]) async throws(CancellationError) -> [WindowId: DetectedWindow] {
        if windows.isEmpty { return [:] } // An idle heavy refresh classifies nothing: no window server query
        let levels = onScreenWindowLevels()
        var toClassify: [AppInfo: [WindowId]] = [:]
        for (app, ids) in windows {
            // An off-screen window whose kind depends on its level has no kind yet: no AX job for it
            let ids = kindNeedsWindowLevel(app.knownBundleId) ? ids.filter { levels[$0.raw] != nil } : ids
            if !ids.isEmpty { toClassify[app] = ids }
        }
        return try await observe(toClassify) { app in
            let classifier = app.classifier
            return { @Sendable axApp, raws, isAbandoned in
                let activationPolicy = classifier.nsApp.activationPolicy // An XPC: once per app
                return eachUntilAbandoned(raws, isAbandoned) { raw in
                    let level = levels[raw]
                    guard let window = axApp.window(raw),
                          let kind = window.getWindowType(axApp: axApp.element, classifier.appId, activationPolicy, level)
                    else { return nil }
                    return DetectedWindow(kind: kind, rect: axApp.rect(raw), level: level)
                }
            }
        }
    }

    func nativeFacts(_ windows: [AppInfo: [WindowId]]) async throws(CancellationError) -> [WindowId: NativeFacts] {
        try await observe(windows) { _ in
            { @Sendable axApp, raws, isAbandoned in axApp.nativeFacts(raws, isAbandoned) }
        }
    }

    func debugInfos(_ windows: [AppInfo: [WindowId]]) async throws(CancellationError) -> [WindowId: WindowDebugInfo] {
        let levels = onScreenWindowLevels()
        return try await observe(windows) { app in
            let read = debugInfoRead(app, levels)
            return { @Sendable axApp, raws, isAbandoned in eachUntilAbandoned(raws, isAbandoned) { raw in read(axApp, raw) } }
        }
    }

    func observedRect(_ id: WindowId) async throws(CancellationError) -> Rect? {
        guard let ax = liveApp(of: id)?.ax else { return nil }
        let raw = id.raw
        return try await ax.call { @Sendable app, _ in app.rect(raw) }
    }

    // MARK: Single reads

    func rect(_ id: WindowId) async -> Rect? {
        await read(id) { app, raw in app.rect(raw) }
    }

    func title(_ id: WindowId) async -> String? {
        await read(id) { app, raw in app.window(raw)?.get(Ax.titleAttr) }
    }

    func facts(_ id: WindowId) async -> NativeFactsRead {
        await read(id) { app, raw in app.nativeFacts(of: raw) } ?? .closed
    }

    func kind(_ id: WindowId) async -> AxUiElementWindowType? {
        guard let app = liveApp(of: id) else { return nil }
        let classifier = app.classifier
        let level = onScreenWindowLevels()[id.raw]
        return await read(id) { @Sendable axApp, raw in
            axApp.window(raw)?.getWindowType(axApp: axApp.element, classifier.appId, classifier.nsApp.activationPolicy, level)
        }
    }

    func windowCount(_ app: AppInfo) async -> Int? {
        guard let ax = apps[app.pid]?.ax else { return nil }
        return await ax.run { $0.element.get(Ax.windowsAttr)?.count }
    }

    func debugInfo(_ id: WindowId) async -> WindowDebugInfo? {
        guard let app = liveApp(of: id), let ax = app.ax else { return nil }
        let read = debugInfoRead(app, onScreenWindowLevels())
        let raw = id.raw
        return await ax.run { axApp in read(axApp, raw) }
    }

    // MARK: Effects

    /// Two jobs per app: its shown workspaces' placements, then its parks, each in the batch's order. The apps run their
    /// jobs in parallel, so a parks job waits, before its first write, until every app has run its shown placements (at
    /// most ``parkWaitLimit``): a window leaves for its corner only once the windows that replace it are there, see
    /// ``ShownJobs``
    func apply(_ batch: [Placement]) {
        var shown: [pid_t: (ax: AxApp, placements: [Placement])] = [:]
        var parks: [pid_t: (ax: AxApp, placements: [Placement])] = [:]
        for placement in batch {
            guard let app = liveApp(of: placement.windowId), let ax = app.ax else { continue }
            if case .park = placement {
                parks[app.info.pid, default: (ax, [])].placements.append(placement)
            } else {
                shown[app.info.pid, default: (ax, [])].placements.append(placement)
            }
        }
        let shownJobs = ShownJobs(deadline: .now() + parkWaitLimit)
        for (ax, placements) in shown.values {
            ax.postPlacements(placements, .shown(shownJobs))
        }
        for (ax, placements) in parks.values {
            ax.postPlacements(placements, .parks(waitingFor: shownJobs))
        }
    }

    /// A FIFO read: it sees the window before the session's placements
    func rememberFloatingSize(_ id: WindowId) {
        let raw = id.raw
        liveApp(of: id)?.ax?.post { app in app.rememberFloatingSize(raw) }
    }

    /// Runs even if a placement of the window is posted after it (the layout of the same session)
    func restoreFloatingSize(_ id: WindowId) {
        let raw = id.raw
        liveApp(of: id)?.ax?.postWindowWrite(raw) { app in app.restoreFloatingSize(raw) }
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
        liveApp(of: id)?.ax?.postWindowWrite(raw) { app in app.close(raw) }
    }

    /// Cancels a pending placement of the window, never the reverse
    func setNative(_ id: WindowId, _ change: NativeChange) {
        let raw = id.raw
        liveApp(of: id)?.ax?.postWindowWrite(raw) { app in
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

    func warpMouse(to point: CGPoint) -> Bool {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else {
            return false
        }
        event.post(tap: .cghidEventTap)
        return true
    }

    func launch(_ executable: String, _ arguments: [String], environment: [String: String]) -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.environment = environment
        return (try? process.run()) != nil
    }

    // MARK: Termination

    nonisolated func restoreForTermination() {
        guard let monitors = terminationMonitors.withLock({ $0 }) else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                restoreWindowsOnMainThread(world.windows.values.compactMap { window in
                    // The restore may run when something went wrong (e.g. some windows are unbound). That's why it
                    // doesn't read `.parent`
                    liveApp(of: window.windowId)?.ax.map { (app: $0, windowId: window.windowId.raw) }
                }, monitors)
            }
        } else {
            restoreWindowsOffMainThread(terminationApps.withLock { Array($0.values) }, monitors)
        }
    }

    // MARK: The registry

    /// The app of a registered window
    private func liveApp(of id: WindowId) -> LiveApp? {
        world.windows[id].flatMap { apps[$0.app.pid] }
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

    /// nil if the app didn't answer
    private func aliveWindowIds(_ app: LiveApp, frontmostAppBundleId: String?) async throws(CancellationError) -> [UInt32]? {
        if app.nsApp.isTerminated {
            destroy(app)
            return []
        }
        guard let ax = app.ax else { return [] }
        let isLockScreen = frontmostAppBundleId == lockScreenAppBundleId
        let alive = try await ax.call { @Sendable app, isAbandoned in app.refreshWindows(isLockScreen: isLockScreen, isAbandoned) }
        if let alive { app.windowsCount = alive.count }
        return alive
    }

    private func destroy(_ app: LiveApp) {
        let pid = app.info.pid
        apps.removeValue(forKey: pid)
        terminationApps.withLock { _ = $0.removeValue(forKey: pid) }
        app.ax = nil
    }

    /// An observe read: one abandonable call per app (see ``AxApp/call(_:)``), the apps in parallel. `read` makes the body for
    /// an app's windows on main; the body runs on the app's thread and stops between windows once the call is abandoned. A
    /// window whose app is gone, or that the body skips, is missing from the result. The caller tells each window's app: a
    /// window that isn't registered yet has no other route to it
    private func observe<T: Sendable>(
        _ windows: [AppInfo: [WindowId]],
        _ read: (LiveApp) -> ObserveBody<T>,
    ) async throws(CancellationError) -> [WindowId: T] {
        var calls: [(AxApp, [UInt32], ObserveBody<T>)] = []
        for (app, ids) in windows {
            guard let app = apps[app.pid], let ax = app.ax else { continue }
            calls.append((ax, ids.map(\.raw), read(app)))
        }
        do {
            return try await withThrowingTaskGroup(of: [(UInt32, T)].self) { group in
                for (ax, raws, body) in calls {
                    group.addTask { @Sendable in try await ax.call { @Sendable app, isAbandoned in body(app, raws, isAbandoned) } }
                }
                var result: [WindowId: T] = [:]
                for try await pairs in group {
                    for (raw, value) in pairs { result[WindowId(raw: raw)] = value }
                }
                return result
            }
        } catch {
            throw CancellationError() // The only error of the reads
        }
    }

    /// The dump of a window for `debug-windows`: what main knows about the app, captured for the app's thread
    private func debugInfoRead(_ app: LiveApp, _ levels: [UInt32: MacOsWindowLevel]) -> @Sendable (isolated AxApp, UInt32) -> WindowDebugInfo? {
        let nsApp = app.nsApp
        let appInfoDic: [String: Any] = nsApp.bundleURL.flatMap { Bundle(url: $0) }?.infoDictionary ?? [:]
        let appVersionShort = appInfoDic["CFBundleShortVersionString"] as? String
        let appVersion = appInfoDic["CFBundleVersion"] as? String
        let execUrl = nsApp.executableURL?.description
        let bundleUrl = nsApp.bundleURL?.description
        let classifier = app.classifier
        return { @Sendable axApp, raw in
            guard let window = axApp.window(raw) else { return nil }
            let windowLevel = levels[raw]
            let activationPolicy = classifier.nsApp.activationPolicy // An XPC
            return WindowDebugInfo(
                axWindow: dumpAxRecursive(window, .window),
                axApp: dumpAxRecursive(axApp.element, .app),
                windowLevel: windowLevel,
                appVersionShort: appVersionShort,
                appVersion: appVersion,
                activationPolicy: activationPolicy.prettyDescription,
                execUrl: execUrl,
                bundleUrl: bundleUrl,
                isDialog: window.isDialogHeuristic(classifier.appId, windowLevel),
                isWindow: window.isWindowHeuristic(axApp: axApp.element, classifier.appId, activationPolicy, windowLevel),
            )
        }
    }

    /// A read of the window's app that waits for it, see ``AxApp/run(_:)``. nil if the app is gone
    private func read<T: Sendable>(_ id: WindowId, _ body: @escaping @Sendable (isolated AxApp, UInt32) -> T?) async -> T? {
        guard let ax = liveApp(of: id)?.ax else { return nil }
        let raw = id.raw
        return await ax.run { app in body(app, raw) }
    }
}

/// The body of an observe read on the app's thread: the values of the windows, until `isAbandoned`
private typealias ObserveBody<T> = @Sendable (isolated AxApp, _ windows: [UInt32], _ isAbandoned: () -> Bool) -> [(UInt32, T)]

/// The values of the windows that `read` returns one for, until the call is abandoned (at cancellation or termination): a
/// batch doesn't keep a busy app's thread
nonisolated private func eachUntilAbandoned<T>(_ raws: [UInt32], _ isAbandoned: () -> Bool, _ read: (UInt32) -> T?) -> [(UInt32, T)] {
    var result: [(UInt32, T)] = []
    for raw in raws {
        if isAbandoned() { break }
        if let value = read(raw) { result.append((raw, value)) }
    }
    return result
}

/// The latest-wins slot of the native focus's slow path: a newer focus request makes a pending one stale
nonisolated private let nativeFocusGeneration: Atomic<UInt64> = Atomic(0)

/// How long the parks of a batch wait for the apps that show windows: a hung app's windows don't hold the others in place
nonisolated private let parkWaitLimit: DispatchTimeInterval = .milliseconds(200)

/// A registered app, main's side. Its AX state and calls live in ``AxApp``, on the app's own thread
private final class LiveApp {
    let info: AppInfo
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
    }

    /// What the window classifier needs from main, captured for the app's thread
    var classifier: WindowClassifier { WindowClassifier(appId: info.knownBundleId, nsApp: nsApp) }
}

nonisolated private struct WindowClassifier: Sendable {
    let appId: KnownBundleId?
    /// Its activationPolicy is an XPC: read it on the app's thread
    let nsApp: NSRunningApplication
}

/// The level of every on-screen window: one query per classification. An off-screen window (minimized, of a hidden app, on
/// another Space) is missing: its level is unknown (RB-35, RB-85)
private func onScreenWindowLevels() -> [UInt32: MacOsWindowLevel] {
    let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
    guard let windows = CGWindowListCopyWindowInfo(options, CGWindowID(0)) as? [NSDictionary] else { return [:] }
    var result: [UInt32: MacOsWindowLevel] = [:]
    for window in windows {
        guard let layer = (window[kCGWindowLayer] as? NSNumber)?.intValue,
              let windowId = (window[kCGWindowNumber] as? NSNumber)?.uint32Value
        else { continue }
        result[windowId] = .new(windowLevel: layer)
    }
    return result
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
