import AppKit
import Common
import Synchronization

/// The main actor's facade of an app. Its AX state and calls live in ``AxApp``, on the app's own thread
final class MacApp: nonisolated AbstractApp { // nonisolated: Hashable compares the pid
    /*conforms*/ nonisolated let pid: Int32
    /*conforms*/ let rawAppBundleId: String?
    let appId: KnownBundleId?
    let nsApp: NSRunningApplication
    /// nil once the app is destroyed: later calls do nothing. The actor then deinits on its thread after its last job
    private var ax: AxApp?
    /// Main's mirror for the native focus fast path (#101), updated by each refresh
    private var windowsCount = 0
    var lastNativeFocusedWindowId: UInt32? = nil

    /*conforms*/ var name: String? { nsApp.localizedName }
    /*conforms*/ var execPath: String? { nsApp.executableURL?.path }
    /*conforms*/ var bundlePath: String? { nsApp.bundleURL?.path }

    // todo think if it's possible to integrate this global mutable state to https://github.com/nikitabobko/AeroSpace/issues/1215
    //      and make deinitialization automatic in deinit
    static var allAppsMap: [pid_t: MacApp] = [:]
    /// Registrations in progress. Everyone who asks for the app meanwhile awaits the same task
    private static var pendingRegistrations: [pid_t: Task<Void, Never>] = [:]
    private static var failedRegistrations: [pid_t: RegistrationBackoff] = [:]
    private static var backoffObservers: [any NSObjectProtocol] = []
    /// The latest-wins slot of the native focus's slow path: a newer focus request makes a pending one stale
    nonisolated private static let nativeFocusGeneration: Atomic<UInt64> = Atomic(0)

    private init(_ nsApp: NSRunningApplication, _ ax: AxApp) {
        self.nsApp = nsApp
        self.ax = ax
        self.pid = nsApp.processIdentifier
        self.rawAppBundleId = nsApp.bundleIdentifier
        self.appId = nsApp.bundleIdentifier.flatMap { KnownBundleId.init(rawValue: $0) }
    }

    @discardableResult
    static func getOrRegister(_ nsApp: NSRunningApplication, pid: pid_t? = nil) async throws -> MacApp? {
        let pid = pid ?? nsApp.processIdentifier
        // Look up first (saves a bundleIdentifier XPC): the lock screen and AeroSpace itself are never registered
        if let existing = allAppsMap[pid] { return existing }
        // Don't perceive any of the lock screen windows as real windows
        // Otherwise, false positive ax notifications might trigger that lead to gcWindows
        if nsApp.bundleIdentifier == lockScreenAppBundleId { return nil }
        // AX requests crash if you send them to yourself
        if pid == myPid { return nil }

        try checkCancellation()
        guard let registration = pendingRegistrations[pid] ?? startRegistration(nsApp, pid) else { return nil }
        await registration.value // Not abandonable: it waits for the app's subscription
        try checkCancellation()
        return allAppsMap[pid]
    }

    /// nil while a failed registration of the app backs off (RB-113)
    private static func startRegistration(_ nsApp: NSRunningApplication, _ pid: pid_t) -> Task<Void, Never>? {
        if let backoff = failedRegistrations[pid], ContinuousClock.now < backoff.retryAt { return nil }
        let threadName = "AxAppThread \(nsApp.idForDebug)"
        let registration = Task.startUnstructured { @MainActor in
            let ax = AxApp(pid: pid, threadName: threadName)
            let isSubscribed = await ax.subscribe()
            pendingRegistrations[pid] = nil
            if isSubscribed {
                failedRegistrations[pid] = nil
                allAppsMap[pid] = MacApp(nsApp, ax)
                axAppsForTermination.withLock { $0[pid] = ax }
            } else { // `ax` deinits: its thread exits
                failedRegistrations[pid] = RegistrationBackoff(after: failedRegistrations[pid], now: .now)
                forgetFailedRegistrationsOnLaunchAndActivation()
            }
        }
        pendingRegistrations[pid] = registration
        return registration
    }

    /// Launching, activating or terminating an app forgets its failed registrations (RB-113)
    private static func forgetFailedRegistrationsOnLaunchAndActivation() {
        if !backoffObservers.isEmpty { return }
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        backoffObservers = names.map { name in
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main, using: forgetFailedRegistration)
        }
    }

    nonisolated private static func forgetFailedRegistration(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        MainActor.assumeIsolated { // The observers' queue is .main
            _ = failedRegistrations.removeValue(forKey: pid)
        }
    }

    func closeAndUnregisterAxWindow(_ windowId: UInt32) {
        if serverArgs.isReadOnly { return }
        ax?.postWindowWrite(windowId) { app, _ in app.close(windowId) }
    }

    // todo merge together with detectNewWindows
    func getFocusedWindow(_ cm: CancellationMode) async throws -> Window? {
        guard let windowId = try await read(cm, { $0.focusedWindowId() }) else { return nil }
        return try await MacWindow.getOrRegister(windowId: windowId, macApp: self)
    }

    func nativeFocus(_ windowId: UInt32) {
        if serverArgs.isReadOnly { return }
        let generation = MacApp.nativeFocusGeneration.wrappingAdd(1, ordering: .sequentiallyConsistent).newValue
        // Performance optimization. If possible avoid doing AX requests
        // (important for apps which are slow at responding even such basic AX requests. E.g. Godot)
        // Beware of the macOS bug: https://github.com/nikitabobko/AeroSpace/issues/101
        if (!NSScreen.screensHaveSeparateSpaces || monitorInfos.count == 1) &&
            (lastNativeFocusedWindowId == windowId || windowsCount == 1)
        {
            nsApp.activateForNativeFocus()
        } else {
            ax?.post { [nsApp] app in
                if MacApp.nativeFocusGeneration.load(ordering: .sequentiallyConsistent) == generation {
                    app.focus(windowId, nsApp)
                }
            }
        }
    }

    func setAxFrame(_ windowId: UInt32, _ topLeft: CGPoint?, _ size: CGSize?) {
        ax?.postWindowWrite(windowId) { app, isLatest in app.place(windowId, topLeft, size, isLatest) }
    }

    /// Cancels a pending setAxFrame of the window, never the reverse
    func setAxAttr<Attr: WritableAttr>(_ windowId: UInt32, _ attr: Attr, _ value: Attr.T) where Attr.T: Sendable {
        ax?.postWindowWrite(windowId) { app, _ in app.window(windowId)?.set(attr, value) }
    }

    func getAxWindowsCount(_ cm: CancellationMode) async throws -> Int? {
        try await read(cm) { $0.element.get(Ax.windowsAttr)?.count }
    }

    func getAxRect(_ windowId: UInt32, _ cm: CancellationMode) async throws -> Rect? {
        try await read(cm) { $0.rect(windowId) }
    }

    func isWindowHeuristic(_ windowId: UInt32, _ windowLevel: MacOsWindowLevel?, _ cm: CancellationMode) async throws -> Bool {
        try await read(cm) { [nsApp, appId] app in
            app.window(windowId)?.isWindowHeuristic(axApp: app.element, appId, nsApp.activationPolicy, windowLevel)
        } == true
    }

    func getAxUiElementWindowType(_ windowId: UInt32, _ windowLevel: MacOsWindowLevel?, _ cm: CancellationMode) async throws -> AxUiElementWindowType {
        try await read(cm) { [nsApp, appId] app in
            app.window(windowId)?.getWindowType(axApp: app.element, appId, nsApp.activationPolicy, windowLevel)
        } ?? .window
    }

    func isDialogHeuristic(_ windowId: UInt32, _ windowLevel: MacOsWindowLevel?, _ cm: CancellationMode) async throws -> Bool {
        try await read(cm) { [appId] app in app.window(windowId)?.isDialogHeuristic(appId, windowLevel) } == true
    }

    func dumpWindowAxInfo(windowId: UInt32, _ cm: CancellationMode) async throws -> OrderedJson.JsonDict {
        try await read(cm) { app in app.window(windowId).map { dumpAxRecursive($0, .window) } } ?? [:]
    }

    func dumpAppAxInfo(_ cm: CancellationMode) async throws -> OrderedJson.JsonDict {
        try await read(cm) { app in dumpAxRecursive(app.element, .app) } ?? [:]
    }

    func getAxAttr<Attr: ReadableAttr>(_ windowId: UInt32, _ attr: Attr, _ cm: CancellationMode) async throws -> Attr.T? where Attr.T: Sendable {
        try await read(cm) { app in app.window(windowId)?.get(attr) }
    }

    func getMacosFullscreenAndMinimized(_ windowId: UInt32, _ cm: CancellationMode) async throws -> (isFullscreen: Bool, isMinimized: Bool)? {
        try await read(cm) { $0.fullscreenAndMinimized(windowId) }
    }

    static func refreshAllAndGetAliveWindowIds(frontmostAppBundleId: String?) async throws -> [MacApp: [UInt32]] {
        for (_, app) in MacApp.allAppsMap { // gc dead apps
            try checkCancellation()
            if app.nsApp.isTerminated {
                app.destroy()
            }
        }
        return try await withThrowingTaskGroup(of: (pid_t, [UInt32]).self, returning: [MacApp: [UInt32]].self) { group in
            var refreshedPids: Set<pid_t> = []
            func refreshTheApp(_ nsApp: NSRunningApplication) {
                let pid = nsApp.processIdentifier // Free right after activationPolicy, an XPC after a suspension point
                refreshedPids.insert(pid)
                group.addTask { @Sendable @MainActor in
                    guard let app = try await MacApp.getOrRegister(nsApp, pid: pid) else { return (pid, []) }
                    return (pid, try await app.refreshAndGetAliveWindowIds(frontmostAppBundleId: frontmostAppBundleId))
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
            for (_, app) in MacApp.allAppsMap where !refreshedPids.contains(app.pid) {
                try checkCancellation()
                // "About this Mac" window, TouchID, and a lot of other utility windows
                // We don't monitor them actively as we do for regular apps, but if a window of one of those utility
                // apps got focused it will end up in allAppsMap
                // Don't re-read activationPolicy: after a yield it can disagree with the scan, and an app that became
                // regular in between would be refreshed by neither loop
                refreshTheApp(app.nsApp)
            }
            var result: [MacApp: [UInt32]] = [:]
            for try await (pid, windowIds) in group {
                if let app = MacApp.allAppsMap[pid] {
                    result[app] = windowIds
                }
            }
            return result
        }
    }

    private func refreshAndGetAliveWindowIds(frontmostAppBundleId: String?) async throws -> [UInt32] {
        if nsApp.isTerminated {
            destroy()
            return []
        }
        guard let ax else { return [] }
        let isLockScreen = frontmostAppBundleId == lockScreenAppBundleId
        let alive = try await ax.call { app, isAbandoned in app.refreshWindows(isLockScreen: isLockScreen, isAbandoned) }
        windowsCount = alive.count
        return alive
    }

    private func destroy() {
        MacApp.allAppsMap.removeValue(forKey: pid)
        axAppsForTermination.withLock { _ = $0.removeValue(forKey: pid) }
        ax = nil
    }

    /// The actor, for termination. nil once the app is destroyed
    var axForTermination: AxApp? { ax }

    /// A read on the app's thread; nil once the app is destroyed.
    /// - `.cancellable` (the refresh): abandoned when the caller is cancelled, so a hung app can't hold the refresh.
    /// - `.nonCancellable` (commands): waits for the app.
    private func read<T: Sendable>(_ cm: CancellationMode, _ body: @escaping @Sendable (isolated AxApp) -> T?) async throws -> T? {
        guard let ax else { return nil }
        return switch cm {
            case .cancellable: try await ax.call { app, _ in body(app) }
            case .nonCancellable: await ax.run(body)
        }
    }
}

/// RB-113: after an app's AX subscription fails, its registration is retried after 1 s, then 2 s, 4 s, … up to 60 s,
/// instead of on every refresh. Launching, activating or terminating the app forgets the failures
nonisolated struct RegistrationBackoff: Equatable {
    let delay: Duration
    let retryAt: ContinuousClock.Instant

    init(after previous: RegistrationBackoff?, now: ContinuousClock.Instant) {
        delay = previous.map { min($0.delay * 2, .seconds(60)) } ?? .seconds(1)
        retryAt = now + delay
    }
}
