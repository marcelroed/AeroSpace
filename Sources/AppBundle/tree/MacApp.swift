import AppKit
import Common

// Potential alternative implementation
// https://github.com/swiftlang/swift-evolution/blob/main/proposals/0392-custom-actor-executors.md
// (only available since macOS 14)
final class MacApp: AbstractApp {
    /*conforms*/ let pid: Int32
    /*conforms*/ let rawAppBundleId: String?
    let appId: KnownBundleId?
    let nsApp: NSRunningApplication
    private let axApp: ThreadGuardedValue<AXUIElement>
    private let appAxSubscriptions: ThreadGuardedValue<[AxSubscription]> // keep subscriptions in memory
    private let windows: ThreadGuardedValue<[UInt32: AxWindow]> = .init([:])
    private var windowsCount = 0
    var lastNativeFocusedWindowId: UInt32? = nil
    private var thread: Thread?
    private var setFrameJobs: [UInt32: RunLoopJob] = [:]
    @MainActor private static var focusJob: RunLoopJob? = nil

    /*conforms*/ var name: String? { nsApp.localizedName }
    /*conforms*/ var execPath: String? { nsApp.executableURL?.path }
    /*conforms*/ var bundlePath: String? { nsApp.bundleURL?.path }

    // todo think if it's possible to integrate this global mutable state to https://github.com/nikitabobko/AeroSpace/issues/1215
    //      and make deinitialization automatic in deinit
    @MainActor static var allAppsMap: [pid_t: MacApp] = [:]
    @MainActor private static var wipPids: [pid_t: AwaitableOneTimeBroadcastLatch] = [:]

    private init(
        _ nsApp: NSRunningApplication,
        _ axApp: AXUIElement,
        _ axSubscriptions: [AxSubscription],
        _ thread: Thread,
    ) {
        self.nsApp = nsApp
        self.axApp = .init(axApp)
        self.pid = nsApp.processIdentifier
        self.rawAppBundleId = nsApp.bundleIdentifier
        self.appId = nsApp.bundleIdentifier.flatMap { KnownBundleId.init(rawValue: $0) }
        assert(!axSubscriptions.isEmpty)
        self.appAxSubscriptions = .init(axSubscriptions)
        self.thread = thread
    }

    @MainActor
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
        if let wip = wipPids[pid] {
            try await wip.await()
            return allAppsMap[pid]
        }
        let wip = AwaitableOneTimeBroadcastLatch()
        wipPids[pid] = wip

        let thread = Thread {
            $axTaskLocalAppThreadToken.withValue(AxAppThreadToken(pid: pid, idForDebug: nsApp.idForDebug)) {
                let axApp = AXUIElementCreateApplication(nsApp.processIdentifier)
                let handlers: HandlerToNotifKeyMapping = unsafe [
                    (refreshObs, [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification]),
                ]
                let job = RunLoopJob(.cancellable)
                let subscriptions = (try? unsafe AxSubscription.bulkSubscribe(nsApp, axApp, job, handlers)) ?? []
                let isGood = !subscriptions.isEmpty
                let app = isGood ? MacApp(nsApp, axApp, subscriptions, Thread.current) : nil

                let appAxSubscriptionsThreadGuarded = app?.appAxSubscriptions
                let windowsThreadGuarded = app?.windows
                let axAppThreadGuarded = app?.axApp

                Task.startUnstructured { @MainActor in
                    allAppsMap[pid] = app
                    wipPids[pid] = nil
                    await wip.signalToAll()
                }
                if isGood {
                    CFRunLoopRun()

                    // Destroy AX objects in reverse order of their creation
                    appAxSubscriptionsThreadGuarded?.destroy()
                    windowsThreadGuarded?.destroy()
                    axAppThreadGuarded?.destroy()
                }
            }
        }
        thread.name = "AxAppThread \(nsApp.idForDebug)"
        thread.start()

        try await wip.await()
        return allAppsMap[pid]
    }

    func closeAndUnregisterAxWindow(_ windowId: UInt32) {
        if serverArgs.isReadOnly { return }
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        _ = withWindowAsync(windowId, .cancellable) { [windows] window, job in
            guard let closeButton = window.get(Ax.closeButtonAttr) else { return }
            if AXUIElementPerformAction(closeButton.cast, kAXPressAction as CFString) == .success {
                windows.threadGuarded.removeValue(forKey: windowId)
            }
        }
    }

    // todo merge together with detectNewWindows
    func getFocusedWindow(_ cm: CancellationMode) async throws -> Window? {
        let windowId = try await thread?.runInLoop(cm) { [nsApp, axApp, windows] job in
            try axApp.threadGuarded.get(Ax.focusedWindowAttr)
                .flatMap { try windows.threadGuarded.getOrRegisterAxWindow(windowId: $0.windowId, $0.ax.cast, nsApp, job) }?
                .windowId
        }
        guard let windowId else { return nil }
        return try await MacWindow.getOrRegister(windowId: windowId, macApp: self)
    }

    @MainActor func nativeFocus(_ windowId: UInt32) {
        if serverArgs.isReadOnly { return }
        MacApp.focusJob?.cancel()
        // Performance optimization. If possible avoid doing AX requests
        // (important for apps which are slow at responding even such basic AX requests. E.g. Godot)
        // Beware of the macOS bug: https://github.com/nikitabobko/AeroSpace/issues/101
        if (!NSScreen.screensHaveSeparateSpaces || monitorInfos.count == 1) &&
            (lastNativeFocusedWindowId == windowId || windowsCount == 1)
        {
            nsApp.activate(options: .activateIgnoringOtherApps)
        } else {
            MacApp.focusJob = withWindowAsync(windowId, .cancellable) { [nsApp] window, job in
                // Raise firstly to make sure that by the time we activate the app, the window would be already on top
                window.set(Ax.isMainAttr, true)
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                nsApp.activate(options: .activateIgnoringOtherApps)
            }
        }
    }

    func setAxFrame(_ windowId: UInt32, _ topLeft: CGPoint?, _ size: CGSize?) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = withWindowAsync(windowId, .cancellable) { [axApp] window, job in
            try disableAnimations(app: axApp.threadGuarded, job) {
                try setFrame(window, topLeft, size, job)
            }
        }
    }

    func setAxFrameForTermination(_ windowId: UInt32, _ topLeft: CGPoint?, _ size: CGSize?) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        // A dying thread would never run the job. See isDyingThread
        guard let thread, !isDyingThread(thread) else { return }
        let semaphore = DispatchSemaphore(value: 0)
        // Not withWindowAsync: it skips the body if the window is already gone from `windows`, and the wait would never end
        thread.runInLoopAsync(job: RunLoopJob(.nonCancellable)) { [axApp, windows] job in
            defer { semaphore.signal() }
            guard let window = windows.threadGuarded[windowId] else { return }
            try? disableAnimations(app: axApp.threadGuarded, job) {
                try setFrame(window.ax, topLeft, size, job)
            }
        }
        semaphore.wait()
    }

    func getAxWindowsCount(_ cm: CancellationMode) async throws -> Int? {
        try await thread?.runInLoop(cm) { [axApp] job in
            axApp.threadGuarded.get(Ax.windowsAttr)?.count
        }
    }

    func getAxRect(_ windowId: UInt32, _ cm: CancellationMode) async throws -> Rect? {
        try await withWindow(windowId, cm) { window, job in
            try AppBundle.getAxRect(window: window, job: job)
        }
    }

    func getAxRectForTermination(_ windowId: UInt32) -> Rect? {
        guard let thread, !isDyingThread(thread) else { return nil } // See setAxFrameForTermination
        let future = CompletableFuture<Rect?>()
        // Not withWindowAsync: see setAxFrameForTermination. Complete on every path
        thread.runInLoopAsync(job: RunLoopJob(.nonCancellable)) { [windows] job in
            future.complete(windows.threadGuarded[windowId].flatMap { try? AppBundle.getAxRect(window: $0.ax, job: job) })
        }
        return future.blockingGet()
    }

    func isWindowHeuristic(_ windowId: UInt32, _ windowLevel: MacOsWindowLevel?, _ cm: CancellationMode) async throws -> Bool {
        return try await withWindow(windowId, cm) { [nsApp, axApp, appId] window, job in
            window.isWindowHeuristic(axApp: axApp.threadGuarded, appId, nsApp.activationPolicy, windowLevel)
        } == true
    }

    func getAxUiElementWindowType(_ windowId: UInt32, _ windowLevel: MacOsWindowLevel?, _ cm: CancellationMode) async throws -> AxUiElementWindowType {
        return try await withWindow(windowId, cm) { [nsApp, axApp, appId] window, job in
            window.getWindowType(axApp: axApp.threadGuarded, appId, nsApp.activationPolicy, windowLevel)
        } ?? .window
    }

    func isDialogHeuristic(_ windowId: UInt32, _ windowLevel: MacOsWindowLevel?, _ cm: CancellationMode) async throws -> Bool {
        try await withWindow(windowId, cm) { [appId] window, job in
            window.isDialogHeuristic(appId, windowLevel)
        } == true
    }

    /// Like setAxFrame, cancels the window's pending frame job
    func setAxAttr<Attr: WritableAttr>(_ windowId: UInt32, _ attr: Attr, _ value: Attr.T) where Attr.T: Sendable {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = withWindowAsync(windowId, .cancellable) { window, job in
            window.set(attr, value)
        }
    }

    func dumpWindowAxInfo(windowId: UInt32, _ cm: CancellationMode) async throws -> OrderedJson.JsonDict {
        try await withWindow(windowId, cm) { window, job in
            dumpAxRecursive(window, .window)
        } ?? [:]
    }

    func dumpAppAxInfo(_ cm: CancellationMode) async throws -> OrderedJson.JsonDict {
        try await thread?.runInLoop(cm) { [axApp] job in
            dumpAxRecursive(axApp.threadGuarded, .app)
        } ?? [:]
    }

    // Calls runInLoop directly: withWindow's body closure would have to capture attr, costing one more closure context
    func getAxAttr<Attr: ReadableAttr>(_ windowId: UInt32, _ attr: Attr, _ cm: CancellationMode) async throws -> Attr.T? {
        try await thread?.runInLoop(cm) { [windows] job in
            windows.threadGuarded[windowId]?.ax.get(attr)
        }
    }

    func getMacosFullscreenAndMinimized(_ windowId: UInt32, _ cm: CancellationMode) async throws -> (isFullscreen: Bool, isMinimized: Bool)? {
        try await withWindow(windowId, cm) { window, job in
            var raw: CFArray?
            // One IPC instead of two. A failed attribute comes back as an AXValue error, which the getters map to nil like a failed get
            let error = unsafe AXUIElementCopyMultipleAttributeValues(window, [Ax.isFullscreenAttr.key, Ax.minimizedAttr.key] as CFArray, [], &raw)
            if error == .success, let values = raw as? [AnyObject], values.count == 2 {
                let isFullscreen = Ax.isFullscreenAttr.getter(values[0]) == true
                return (isFullscreen, !isFullscreen && Ax.minimizedAttr.getter(values[1]) == true)
            }
            // After an AX timeout, treat fullscreen like a timed-out get (false) instead of waiting for it again
            let isFullscreen = error != .cannotComplete && window.get(Ax.isFullscreenAttr) == true
            return (isFullscreen, !isFullscreen && window.get(Ax.minimizedAttr) == true)
        }
    }

    @MainActor
    static func refreshAllAndGetAliveWindowIds(frontmostAppBundleId: String?) async throws -> [MacApp: [UInt32]] {
        for (_, app) in MacApp.allAppsMap { // gc dead apps
            try checkCancellation()
            if app.nsApp.isTerminated {
                await app.destroy()
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
                // Each activationPolicy read is a launchservicesd XPC, and there are hundreds of apps.
                // Yield now and then, so that runLightSession can cancel this refresh instead of waiting for the whole loop
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
            await destroy()
            return []
        }
        guard let thread else { return [] }
        let (alive, dead) = try await thread.runInLoop(.cancellable) { [nsApp, windows, axApp] (job) -> ([UInt32], [UInt32]) in
            let listed = axApp.threadGuarded.get(Ax.windowsAttr) ?? []
            var alive: [UInt32: AxWindow] = windows.threadGuarded
            var dead = [UInt32: AxWindow]()
            // Second line of defence against lock screen. See the first line of defence: closedWindowsCache
            // Second and third lines of defence are technically needed only to avoid potential flickering
            if frontmostAppBundleId != lockScreenAppBundleId {
                for (id, window) in alive {
                    try job.checkCancellation()
                    // A listed CFEqual element has just answered containingWindowId() in the windowsAttr getter
                    let isAlive = listed.contains { $0.ax == window.ax } || window.ax.containingWindowId() != nil
                    if !isAlive {
                        alive[id] = nil
                        dead[id] = window
                    }
                }
            }

            for (id, window) in listed {
                try job.checkCancellation()
                try alive.getOrRegisterAxWindow(windowId: id, window, nsApp, job)
            }

            windows.threadGuarded = alive
            return (Array(alive.keys), Array(dead.keys))
        }
        windowsCount = alive.count
        for windowId in dead {
            setFrameJobs.removeValue(forKey: windowId)?.cancel()
        }
        return alive
    }

    private func destroy() async {
        _ = await Task.startUnstructured { @MainActor [pid] in _ = MacApp.allAppsMap.removeValue(forKey: pid) }.result
        for (_, job) in setFrameJobs {
            job.cancel()
        }
        setFrameJobs = [:]
        thread?.runInLoopAsync(job: RunLoopJob(.nonCancellable)) { job in CFRunLoopStop(CFRunLoopGetCurrent()) }
        thread = nil // Disallow all future job submissions
    }

    private func withWindow<T>(
        _ windowId: UInt32,
        _ cm: CancellationMode,
        _ body: @Sendable @escaping (AXUIElement, RunLoopJob) throws -> T?,
    ) async throws -> T? {
        try await thread?.runInLoop(cm) { [windows] job in
            guard let window = windows.threadGuarded[windowId] else { return nil }
            return try body(window.ax, job)
        }
    }

    private func withWindowAsync(_ windowId: UInt32, _ cm: CancellationMode, _ body: @Sendable @escaping (AXUIElement, RunLoopJob) throws -> ()) -> RunLoopJob {
        thread?.runInLoopAsync(job: RunLoopJob(cm)) { [windows] job in
            guard let window = windows.threadGuarded[windowId] else { return }
            try? body(window.ax, job)
        } ?? .cancelled
    }
}

private final class AxWindow {
    let windowId: UInt32
    let ax: AXUIElement
    // periphery:ignore
    private let axSubscriptions: [AxSubscription] // keep subscriptions in memory

    private init(windowId: UInt32, _ ax: AXUIElement, _ axSubscriptions: [AxSubscription]) {
        self.windowId = windowId
        self.ax = ax
        assert(!axSubscriptions.isEmpty)
        self.axSubscriptions = axSubscriptions
    }

    static func new(windowId: UInt32, _ ax: AXUIElement, _ nsApp: NSRunningApplication, _ job: RunLoopJob) throws -> AxWindow? {
        let handlers: HandlerToNotifKeyMapping = unsafe [
            (refreshObs, [kAXUIElementDestroyedNotification, kAXWindowDeminiaturizedNotification, kAXWindowMiniaturizedNotification]),
            (movedObs, [kAXMovedNotification]),
            (resizedObs, [kAXResizedNotification]),
        ]
        let subscriptions = try unsafe AxSubscription.bulkSubscribe(nsApp, ax, job, handlers)
        return !subscriptions.isEmpty ? AxWindow(windowId: windowId, ax, subscriptions) : nil
    }
}

extension [UInt32: AxWindow] {
    @discardableResult
    fileprivate mutating func getOrRegisterAxWindow(windowId id: UInt32, _ axWindow: AXUIElement, _ nsApp: NSRunningApplication, _ job: RunLoopJob) throws -> AxWindow? {
        if let existing = self[id] { return existing }
        // Delay new window detection if mouse is down
        // It helps with apps that allow dragging their tabs out to create new windows
        // https://github.com/nikitabobko/AeroSpace/issues/1001
        if isLeftMouseButtonDown { return nil }

        if let window = try AxWindow.new(windowId: id, axWindow, nsApp, job) {
            self[id] = window
            return window
        } else {
            return nil
        }
    }
}

private func getAxRect(window: AXUIElement, job: RunLoopJob) throws -> Rect? {
    guard let topLeftCorner = window.get(Ax.topLeftCornerAttr) else { return nil }
    try job.checkCancellation()
    guard let size = window.get(Ax.sizeAttr) else { return nil }
    return Rect(topLeftX: topLeftCorner.x, topLeftY: topLeftCorner.y, width: size.width, height: size.height)
}

private func setFrame(_ window: AXUIElement, _ topLeft: CGPoint?, _ size: CGSize?, _ job: RunLoopJob) throws {
    // Set size and then the position. The order is important https://github.com/nikitabobko/AeroSpace/issues/143
    //                                                        https://github.com/nikitabobko/AeroSpace/issues/335
    if let size { window.set(Ax.sizeAttr, size) }
    try job.checkCancellation()
    if let topLeft { window.set(Ax.topLeftCornerAttr, topLeft) } else { return }
    try job.checkCancellation()
    if let size { window.set(Ax.sizeAttr, size) }
}

// Some undocumented magic
// References: https://github.com/koekeishiya/yabai/commit/3fe4c77b001e1a4f613c26f01ea68c0f09327f3a
//             https://github.com/rxhanson/Rectangle/pull/285
private func disableAnimations<T>(app: AXUIElement, _ job: RunLoopJob, _ body: () throws -> T) throws -> T {
    let wasEnabled = app.get(Ax.enhancedUserInterfaceAttr) == true
    if wasEnabled {
        app.set(Ax.enhancedUserInterfaceAttr, false)
    }
    defer {
        if wasEnabled {
            app.set(Ax.enhancedUserInterfaceAttr, true)
        }
    }
    try job.checkCancellation()
    return try body()
}
