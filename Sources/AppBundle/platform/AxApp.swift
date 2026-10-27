import AppKit
import Common
import Synchronization

/// One app's AX state, isolated to the app's own thread (``AxThreadExecutor``). Every AX call of the app and every
/// notification of its observers runs there, so a hung app blocks only its own thread. ``LivePlatform`` keeps one per app.
/// - Reads are isolated synchronous methods. LivePlatform awaits them (`run`), or makes them abandonable (`call`).
/// - Writes are `post`s: FIFO and never awaited. Each closure that runs here is `@Sendable` with an `isolated AxApp`
///   parameter: a closure that inherits `@MainActor` traps on this thread.
/// - No `await` in its methods: later posts would run in the middle, out of order. No `Task`: it would run off this
///   thread. Nothing spins the run loop: an observer callback would enter the actor in the middle of a method.
actor AxApp {
    nonisolated let pid: pid_t
    /// The latest-wins slot of each window's placement (0f1b849d). See ``postWindowWrite(_:_:)``
    nonisolated let generations: Mutex<WindowGenerations> = Mutex(WindowGenerations())
    private let executor: AxThreadExecutor
    /// Creating it makes no AX call
    let element: AXUIElement
    private var subscription: AxSubscription? = nil
    private var windows: [UInt32: AxWindow] = [:]

    nonisolated var unownedExecutor: UnownedSerialExecutor { unsafe executor.asUnownedSerialExecutor() }

    /// Starts the app's thread. Subscribe before use
    init(pid: pid_t, threadName: String) {
        self.pid = pid
        self.executor = AxThreadExecutor(threadName: threadName)
        self.element = AXUIElementCreateApplication(pid)
    }

    /// Runs on the app's thread once the last reference is gone. Pending posts retain the actor, so they all ran before.
    /// Destroys the AX objects in today's order (9c5fa1aa, dd6b927a): the app's subscription, the windows with theirs,
    /// then (with the actor's storage) the app element
    isolated deinit {
        subscription = nil
        windows = [:]
        executor.shutdown() // Only here: a job enqueued after it would never run
    }

    // MARK: Calls from the main actor

    /// FIFO with every other post and awaited call. For writes: the caller never waits
    nonisolated func post(_ body: @escaping @Sendable (isolated AxApp) -> Void) {
        executor.enqueueRaw { @Sendable [self] in
            self.assumeIsolated { body($0) }
        }
    }

    /// An awaited read that waits for the app, however long it takes. nil without running `body` once termination
    /// started: the restore job waits behind it
    func run<T: Sendable>(_ body: @Sendable (isolated AxApp) -> T?) -> T? {
        if isTerminatingNow() { return nil }
        return body(self)
    }

    /// An awaited read that the caller can abandon, so that a hung app can't hold a refresh. On cancellation it
    /// throws right away. The body is skipped if it hasn't started yet; otherwise it runs to the end here and its result
    /// is dropped. The body can poll `isAbandoned` to stop early, but must then leave the actor's state unchanged.
    /// Termination abandons it too: the restore job waits behind it
    nonisolated func call<T: Sendable>(
        _ body: @escaping @Sendable (isolated AxApp, _ isAbandoned: () -> Bool) -> T,
    ) async throws(CancellationError) -> T {
        try checkCancellation()
        let result: FirstOutcome<Result<T, CancellationError>> = FirstOutcome()
        post { app in
            if result.isResolved { return } // Cancelled before the body started: skip the AX calls
            if isTerminatingNow() {
                result.resolve(.failure(CancellationError()))
            } else {
                let value = body(app) { result.isResolved || isTerminatingNow() }
                result.resolve(isTerminatingNow() ? .failure(CancellationError()) : .success(value))
            }
        }
        return try await result.wait(onCancel: .failure(CancellationError())).get()
    }

    /// For termination, which can't await: posts `body` and waits at most `timeout` for it. false if it timed out (RB-76).
    /// Not on the app's own thread: the job would wait behind the caller
    nonisolated func postAndWait(timeout: DispatchTimeInterval, _ body: @escaping @Sendable (isolated AxApp) -> Void) -> Bool {
        let isDone = DispatchSemaphore(value: 0)
        post { app in
            body(app)
            isDone.signal()
        }
        return isDone.wait(timeout: .now() + timeout) == .success
    }

    nonisolated var isCurrentThread: Bool { executor.isCurrentThread }

    /// Posts a write of one window that runs even if a newer write of the window is posted: an attribute write, a close or
    /// ``restoreFloatingSize(_:)``. It makes the window's pending placements stale (latest wins, 0f1b849d): such a write
    /// cancels a pending placement, never the reverse
    nonisolated func postWindowWrite(_ windowId: UInt32, _ body: @escaping @Sendable (isolated AxApp) -> Void) {
        let generation = generations.withLock { $0.bump(windowId) }
        post { app in
            body(app)
            app.generations.withLock { $0.finish(windowId, generation) }
        }
    }

    /// Posts one job for the app's placements of a batch, in the batch's order. Each placement is its window's latest
    /// write until a newer write of the window is posted (as ``postWindowWrite(_:_:)``), and it stops, also between its AX
    /// calls, once it's stale or termination starts. The job runs `before` and `after` on the app's thread
    nonisolated func postPlacements(
        _ placements: [Placement],
        before: @escaping @Sendable () -> Void = {},
        after: @escaping @Sendable () -> Void = {},
    ) {
        let generations: [UInt64] = self.generations.withLock { generations in placements.map { generations.bump($0.windowId.raw) } }
        post { app in
            before()
            app.place(placements, generations)
            after()
        }
    }

    // MARK: Isolated: AX calls

    /// Registration keeps the app iff this succeeds
    func subscribe() -> Bool {
        subscription = AxSubscription.subscribe(element, [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification], self)
        return subscription != nil
    }

    func window(_ windowId: UInt32) -> AXUIElement? { windows[windowId]?.ax }

    var windowIds: [UInt32] { Array(windows.keys) }

    /// The refresh's read: drops the dead windows, registers the new ones, returns the ids of the alive ones in the app's
    /// order (then the alive ones it didn't list). nil if the app didn't answer (the AX timeout of a hung app): then nothing
    /// changes. Commits nothing if the caller abandons it (the result is dropped then)
    func refreshWindows(isLockScreen: Bool, _ isAbandoned: () -> Bool) -> [UInt32]? {
        let (error, elements) = element.getWithError(Ax.windowElementsAttr)
        if error == .cannotComplete { return nil }
        let listed: [WindowIdAndAxUiElement] = (elements ?? []).compactMap { ax in windowId(of: ax).map { ($0, ax) } }
        var alive = windows
        // Second line of defence against lock screen (964e5b11). See the first line of defence: closedWindowsCache
        // Second and third lines of defence are technically needed only to avoid potential flickering
        if !isLockScreen {
            var isBusy = false
            for (id, window) in alive {
                if isAbandoned() { return [] }
                // Liveness via _AXUIElementGetWindow, not the unreliable kAXUIElementDestroyedNotification (405dec8b).
                // A listed (CFEqual) element is alive: the app has just listed it
                if isBusy || listed.contains(where: { $0.ax == window.ax }) { continue }
                let (error, windowId) = window.ax.containingWindowIdWithError()
                // A timeout is no evidence that the window is gone, and the next call would wait as long
                if error == .cannotComplete {
                    isBusy = true
                } else if windowId == nil {
                    alive[id] = nil
                }
            }
        }
        var order: [UInt32] = []
        for (id, ax) in listed {
            if isAbandoned() { return [] }
            if registerWindow(id, ax, in: &alive) && !order.contains(id) { order.append(id) }
        }
        windows = alive // The dropped windows (and their subscriptions) are released here, on this thread (9c5fa1aa)
        let listedIds = Set(order)
        return order + alive.keys.filter { !listedIds.contains($0) }.sorted()
    }

    func focusedWindowId() -> UInt32? {
        guard let focused = element.get(Ax.focusedWindowElementAttr), let windowId = windowId(of: focused) else { return nil }
        return registerWindow(windowId, focused, in: &windows) ? windowId : nil
    }

    /// The id of a window element that the app listed or focused. A registered window's element is CFEqual to it (pid and
    /// token, compared without IPC), so only a new element costs an `_AXUIElementGetWindow`, which asks the app. nil: not a
    /// window (e.g. Finder's desktop)
    private func windowId(of ax: AXUIElement) -> UInt32? {
        windows.first { $0.value.ax == ax }?.key ?? ax.containingWindowId()
    }

    func rect(_ windowId: UInt32) -> Rect? {
        windows[windowId].flatMap { axRect($0.ax) }
    }

    /// The native states of the windows that are registered. It stops after an AX timeout: the app is busy, each further
    /// read would wait as long, and a timed-out read tells nothing. The windows from there are missing, and so
    /// is a window whose read failed otherwise (e.g. it closed after the listing): a failed read tells nothing either
    func nativeFacts(_ windowIds: [UInt32], _ isAbandoned: () -> Bool) -> [(UInt32, NativeFacts)] {
        var result: [(UInt32, NativeFacts)] = []
        loop: for windowId in windowIds {
            if isAbandoned() { break }
            switch nativeFacts(of: windowId) {
                case .facts(let facts): result.append((windowId, facts))
                case .closed: continue
                case .noAnswer: break loop
            }
        }
        return result
    }

    /// The native states of one window that is registered
    func nativeFacts(of windowId: UInt32) -> NativeFactsRead {
        guard let window = windows[windowId]?.ax else { return .closed }
        // One IPC instead of two. A failed attribute comes back as an AXValue error, which the getters map to nil
        // like a failed get
        let (error, values) = window.getMultiple([Ax.isFullscreenAttr.key, Ax.minimizedAttr.key])
        if error == .cannotComplete { return .noAnswer }
        if error == .invalidUIElement { return .closed }
        let isFullscreen: Bool
        let isMinimized: Bool
        if error == .success, let values, values.count == 2 {
            isFullscreen = Ax.isFullscreenAttr.getter(values[0]) == true
            isMinimized = Ax.minimizedAttr.getter(values[1]) == true
        } else { // An app that can't answer both at once: one read per attribute
            let fullscreenRead = window.getWithError(Ax.isFullscreenAttr)
            if fullscreenRead.error == .cannotComplete { return .noAnswer }
            guard let fullscreen = fact(fullscreenRead) else { return .closed }
            let minimizedRead = window.getWithError(Ax.minimizedAttr)
            if minimizedRead.error == .cannotComplete { return .noAnswer }
            guard let minimized = fact(minimizedRead) else { return .closed }
            (isFullscreen, isMinimized) = (fullscreen, minimized)
        }
        return .facts(NativeFacts(isFullscreen: isFullscreen, isMinimized: !isFullscreen && isMinimized))
    }

    /// See ``postPlacements(_:before:after:)``. The app's animations are off from the batch's first write to its end. The
    /// job ends once the window server shows the tiles that it unparked
    private func place(_ placements: [Placement], _ generations: [UInt64]) {
        var unparkedTiles: [(windowId: UInt32, topLeft: CGPoint)] = []
        let animations = AnimationsOff(element)
        for (placement, generation) in zip(placements, generations) {
            let windowId = placement.windowId.raw
            if let ax = windows[windowId]?.ax {
                let window = AxPlacementWindow(ax: ax, animations: animations) { @Sendable [self] in
                    self.generations.withLock { $0.isLatest(windowId, generation) } && !isTerminatingNow()
                }
                let wasParked = windows[windowId]?.placement.isParked == true
                windows[windowId]?.placement.apply(placement, to: window)
                if wasParked, windows[windowId]?.placement.isParked == false, case .frame(_, let topLeft, _) = placement {
                    unparkedTiles.append((windowId, topLeft))
                }
            }
            self.generations.withLock { $0.finish(windowId, generation) }
        }
        animations.restore()
        waitUntilOnScreen(unparkedTiles)
    }

    /// `layout tiling` and `enable on`, see ``PlacementState/rememberFloatingSize(of:)``
    func rememberFloatingSize(_ windowId: UInt32) {
        guard let ax = windows[windowId]?.ax else { return }
        // It only reads: the animations stay on
        let window = AxPlacementWindow(ax: ax, animations: AnimationsOff(element)) { @Sendable in !isTerminatingNow() }
        windows[windowId]?.placement.rememberFloatingSize(of: window)
    }

    /// `layout floating`, see ``PlacementState/restoreFloatingSize(to:)``
    func restoreFloatingSize(_ windowId: UInt32) {
        guard let window = windows[windowId] else { return }
        let animations = AnimationsOff(element)
        defer { animations.restore() }
        let ax = AxPlacementWindow(ax: window.ax, animations: animations) { @Sendable in !isTerminatingNow() }
        window.placement.restoreFloatingSize(to: ax)
    }

    /// Termination: moves the window to the frame that `monitors` computes from its current rect and last floating size
    func restore(_ windowId: UInt32, _ monitors: TerminationMonitors) {
        guard let window = windows[windowId] else { return }
        let animations = AnimationsOff(element)
        defer { animations.restore() }
        let ax = AxPlacementWindow(ax: window.ax, animations: animations) { @Sendable in true }
        let frame = monitors.restoreFrame(windowRect: ax.rect(), window.placement.lastFloatingSize)
        ax.setFrame(topLeft: frame.topLeft, size: frame.size)
    }

    /// The slow path of native focus (LivePlatform.focus has the fast path, #101)
    func focus(_ windowId: UInt32, _ nsApp: NSRunningApplication) {
        guard let window = windows[windowId]?.ax else { return }
        // Raise firstly to make sure that by the time we activate the app, the window would be already on top
        window.set(Ax.isMainAttr, true)
        window.perform(kAXRaiseAction)
        nsApp.activateForNativeFocus()
    }

    /// On success, unregisters the window
    func close(_ windowId: UInt32) {
        guard let closeButton = windows[windowId]?.ax.get(Ax.closeButtonAttr) else { return }
        if closeButton.cast.perform(kAXPressAction) {
            windows[windowId] = nil
        }
    }

    /// Registers a new window: observes it. false if it isn't registered (#1001, or a failed subscription)
    @discardableResult
    private func registerWindow(_ windowId: UInt32, _ ax: AXUIElement, in windows: inout [UInt32: AxWindow]) -> Bool {
        if windows[windowId] != nil { return true }
        // Delay new window detection if mouse is down
        // It helps with apps that allow dragging their tabs out to create new windows
        // https://github.com/nikitabobko/AeroSpace/issues/1001
        if isLeftMouseButtonDown { return false }
        let notifications: [String] = [
            kAXUIElementDestroyedNotification,
            kAXWindowDeminiaturizedNotification,
            kAXWindowMiniaturizedNotification,
            kAXMovedNotification,
            kAXResizedNotification,
        ]
        guard let subscription = AxSubscription.subscribe(ax, notifications, self) else { return false }
        // The size that `layout floating` and termination restore until the window is floating
        let placement = PlacementState(lastFloatingSize: ax.get(Ax.sizeAttr))
        windows[windowId] = AxWindow(ax: ax, subscription: subscription, placement: placement)
        return true
    }
}

nonisolated private struct AxWindow {
    let ax: AXUIElement
    // periphery:ignore
    let subscription: AxSubscription // Keeps the window observed
    var placement: PlacementState
}

/// The latest-wins slot of each window (0f1b849d). A write bumps its window's generation; it's still the latest while
/// no newer write of that window was posted. An entry lives only while a write of its window is queued or running, so
/// dead windows leave nothing behind (f9c7a90a). The counter is per app and never reused, so a new entry can't match
/// an old generation
nonisolated struct WindowGenerations {
    private var latest: [UInt32: UInt64] = [:]
    private var counter: UInt64 = 0

    mutating func bump(_ windowId: UInt32) -> UInt64 {
        counter += 1
        latest[windowId] = counter
        return counter
    }

    func isLatest(_ windowId: UInt32, _ generation: UInt64) -> Bool { latest[windowId] == generation }

    /// The write is done: forget the window unless a newer write is pending
    mutating func finish(_ windowId: UInt32, _ generation: UInt64) {
        if isLatest(windowId, generation) {
            latest[windowId] = nil
        }
    }
}

/// The one AXObserver callback of every app. It runs on the app's thread: the observers' sources are on its run loop.
/// `refcon` is the unretained app (see AxSubscription). It maps the notification to an ``AxEvent`` and hands it to the
/// main actor, so it never touches the actor's state
nonisolated func axObserverCallback(
    _: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?,
) {
    guard let refcon = unsafe refcon else { return }
    // No strong reference, not even a temporary one: if it were the last one, the isolated deinit would run inline,
    // inside this AXObserver callout, and release the observer whose callout is on the stack. Without it, the last
    // release happens elsewhere, and the deinit runs as a job after the callout
    unsafe Unmanaged<AxApp>.fromOpaque(refcon)._withUnsafeGuaranteedRef { app in
        app.preconditionIsolated()
    }
    let event: AxEvent
    switch notification as String {
        case kAXWindowCreatedNotification: event = .windowCreated
        case kAXFocusedWindowChangedNotification: event = .focusedWindowChanged
        case kAXUIElementDestroyedNotification: event = .destroyed
        case kAXWindowMiniaturizedNotification: event = .miniaturized
        case kAXWindowDeminiaturizedNotification: event = .deminiaturized
        case kAXMovedNotification: event = .moved(windowId: element.containingWindowId().map(WindowId.init(raw:)))
        case kAXResizedNotification: event = .resized(windowId: element.containingWindowId().map(WindowId.init(raw:)))
        default: return
    }
    Task.startUnstructured { @MainActor in
        await world.sessions.onAxEvent(event)
    }
}

/// The window's position and size in one AX call. An app that can't answer both at once gets a read of each
nonisolated private func axRect(_ window: AXUIElement) -> Rect? {
    let (error, values) = window.getMultiple([Ax.topLeftCornerAttr.key, Ax.sizeAttr.key])
    let topLeft: CGPoint?
    let size: CGSize?
    if error == .success, let values, values.count == 2 {
        // A failed attribute comes back as an AXValue error, which the getters map to nil
        (topLeft, size) = (Ax.topLeftCornerAttr.getter(values[0]), Ax.sizeAttr.getter(values[1]))
    } else if error == .cannotComplete || error == .invalidUIElement {
        return nil // The AX timeout of a busy app (each further read would wait as long), or a closed window
    } else {
        (topLeft, size) = (window.get(Ax.topLeftCornerAttr), window.get(Ax.sizeAttr))
    }
    guard let topLeft, let size else { return nil }
    return Rect(topLeftX: topLeft.x, topLeftY: topLeft.y, width: size.width, height: size.height)
}

/// Termination started: the restore job waits behind the app's jobs, so they stop before their next AX call
nonisolated private func isTerminatingNow() -> Bool { isTerminating.load(ordering: .sequentiallyConsistent) }

/// An app can answer the AX writes of a window before it moves the window on screen: cmux moves it ~25 ms later. The parks
/// that wait for the job (LivePlatform.apply) would uncover the desktop in between, so the job waits until the window
/// server shows each tile at its top left corner, at most ``onScreenWaitLimit``
nonisolated private func waitUntilOnScreen(_ tiles: [(windowId: UInt32, topLeft: CGPoint)]) {
    let deadline: DispatchTime = .now() + onScreenWaitLimit
    var pending = tiles
    while true {
        pending.removeAll { tile in
            guard let shown = windowServerTopLeft(tile.windowId) else { return true } // Closed
            return abs(shown.x - tile.topLeft.x) < 1 && abs(shown.y - tile.topLeft.y) < 1
        }
        if pending.isEmpty || DispatchTime.now() >= deadline || isTerminatingNow() { return }
        Thread.sleep(forTimeInterval: 0.001)
    }
}

nonisolated private let onScreenWaitLimit: DispatchTimeInterval = .milliseconds(100)

/// The window's top left corner as the window server shows it. nil once the window is gone
nonisolated private func windowServerTopLeft(_ windowId: UInt32) -> CGPoint? {
    guard let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, windowId) as? [NSDictionary])?.first,
          let bounds = info[kCGWindowBounds] as? NSDictionary,
          let rect = CGRect(dictionaryRepresentation: bounds)
    else { return nil }
    return rect.origin
}

/// A window of the app for ``PlacementState``, on the app's thread
nonisolated private struct AxPlacementWindow: PlacementWindow {
    let ax: AXUIElement
    let animations: AnimationsOff
    let isCurrentNow: @Sendable () -> Bool

    func isCurrent() -> Bool { isCurrentNow() }
    func rect() -> Rect? { axRect(ax) }

    @discardableResult
    func setFrame(topLeft: CGPoint?, size: CGSize?) -> Bool {
        guard isCurrent() else { return false }
        animations.turnOff()
        // Set size and then the position. The order is important https://github.com/nikitabobko/AeroSpace/issues/143
        //                                                        https://github.com/nikitabobko/AeroSpace/issues/335
        if let size { ax.set(Ax.sizeAttr, size) }
        guard isCurrent(), let topLeft else { return false }
        ax.set(Ax.topLeftCornerAttr, topLeft)
        if isCurrent(), let size { ax.set(Ax.sizeAttr, size) }
        return true
    }
}

/// Turns the app's animations off before the first window write, and back on in ``restore()``.
/// Some undocumented magic
/// References: https://github.com/koekeishiya/yabai/commit/3fe4c77b001e1a4f613c26f01ea68c0f09327f3a
///             https://github.com/rxhanson/Rectangle/pull/285
nonisolated private final class AnimationsOff {
    private let app: AXUIElement
    /// nil until the first write
    private var wasEnabled: Bool? = nil

    init(_ app: AXUIElement) { self.app = app }

    func turnOff() {
        if wasEnabled != nil { return }
        let wasEnabled = app.get(Ax.enhancedUserInterfaceAttr) == true
        if wasEnabled {
            app.set(Ax.enhancedUserInterfaceAttr, false)
        }
        self.wasEnabled = wasEnabled
    }

    func restore() {
        if wasEnabled == true {
            app.set(Ax.enhancedUserInterfaceAttr, true)
        }
    }
}

/// A Bool attribute as a fact about the window: a window without the attribute doesn't have the state. nil if the read
/// failed otherwise (e.g. the window closed): it tells nothing
nonisolated private func fact(_ read: (error: AXError, value: Bool?)) -> Bool? {
    switch read.error {
        case .success: read.value == true
        case .attributeUnsupported, .noValue: false
        default: nil
    }
}
