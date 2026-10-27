import AppKit
import Common
import Synchronization

/// One app's AX state, isolated to the app's own thread (``AxThreadExecutor``). Every AX call of the app and every
/// notification of its observers runs there, so a hung app blocks only its own thread. ``LivePlatform`` keeps one per app.
/// - Reads are isolated synchronous methods. LivePlatform awaits them (`run`), or makes them abandonable (`call`).
/// - Writes are `post`s: FIFO and never awaited. Each closure that runs here is `@Sendable` with an `isolated AxApp`
///   parameter, never inferred `@MainActor` (P3).
/// - No `await` and no `Task` inside its methods (P4, P5), and nothing spins the run loop (P2).
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
        executor.shutdown() // P8: only here
    }

    // MARK: Calls from the main actor

    /// FIFO with every other post and awaited call. For writes: the caller never waits
    nonisolated func post(_ body: @escaping @Sendable (isolated AxApp) -> Void) {
        executor.enqueueRaw { @Sendable [self] in
            self.assumeIsolated { body($0) }
        }
    }

    /// An awaited read that waits for the app, however long it takes (P7). nil without running `body` once termination
    /// started: the restore job waits behind it (R2a L2)
    func run<T: Sendable>(_ body: @Sendable (isolated AxApp) -> T?) -> T? {
        if isTerminating.load(ordering: .sequentiallyConsistent) { return nil }
        return body(self)
    }

    /// An awaited read that the caller can abandon, so that a hung app can't hold a refresh (P7). On cancellation it
    /// throws right away. The body is skipped if it hasn't started yet; otherwise it runs to the end here and its result
    /// is dropped. The body can poll `isAbandoned` to stop early, but must then leave the actor's state unchanged.
    /// Termination abandons it too: the restore job waits behind it (R2a L2)
    nonisolated func call<T: Sendable>(
        _ body: @escaping @Sendable (isolated AxApp, _ isAbandoned: () -> Bool) -> T,
    ) async throws(CancellationError) -> T {
        try checkCancellation()
        let box = CallBox<T>()
        let result: Result<T, CancellationError> = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                box.suspend(continuation)
                post { app in
                    func isTerminatingNow() -> Bool { isTerminating.load(ordering: .sequentiallyConsistent) }
                    if box.isResolved { return } // Cancelled before the body started: skip the AX calls
                    if isTerminatingNow() { return box.resolve(.failure(CancellationError())) }
                    let value = body(app) { box.isResolved || isTerminatingNow() }
                    box.resolve(isTerminatingNow() ? .failure(CancellationError()) : .success(value))
                }
            }
        } onCancel: {
            box.resolve(.failure(CancellationError()))
        }
        return try result.get()
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

    /// Posts one job for the app's placements of a batch, in the batch's order (design-m2 D4). Each placement is its
    /// window's latest write until a newer write of the window is posted (as ``postWindowWrite(_:_:)``), and it stops,
    /// also between its AX calls, once it's stale or termination starts
    nonisolated func postPlacements(_ placements: [Placement], isZoom: Bool) {
        let generations: [UInt64] = self.generations.withLock { generations in placements.map { generations.bump($0.windowId.raw) } }
        post { app in app.place(placements, generations, isZoom: isZoom) }
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
        let (error, value) = element.getWithError(Ax.windowsAttr)
        if error == .cannotComplete { return nil }
        let listed = value ?? []
        var alive = windows
        // Second line of defence against lock screen (964e5b11). See the first line of defence: closedWindowsCache
        // Second and third lines of defence are technically needed only to avoid potential flickering
        if !isLockScreen {
            for (id, window) in alive {
                if isAbandoned() { return [] }
                // Liveness via _AXUIElementGetWindow, not the unreliable kAXUIElementDestroyedNotification (405dec8b).
                // PF-1: a listed CFEqual element has just answered containingWindowId() in the windowsAttr getter
                let isAlive = listed.contains { $0.ax == window.ax } || window.ax.containingWindowId() != nil
                if !isAlive {
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
        guard let focused = element.get(Ax.focusedWindowAttr) else { return nil }
        return registerWindow(focused.windowId, focused.ax.cast, in: &windows) ? focused.windowId : nil
    }

    func rect(_ windowId: UInt32) -> Rect? {
        windows[windowId].flatMap { axRect($0.ax) }
    }

    func nativeFacts(_ windowId: UInt32) -> NativeFacts? {
        guard let window = windows[windowId]?.ax else { return nil }
        // PF-3: one IPC instead of two. A failed attribute comes back as an AXValue error, which the getters map to nil like a failed get
        let (error, values) = window.getMultiple([Ax.isFullscreenAttr.key, Ax.minimizedAttr.key])
        if error == .success, let values, values.count == 2 {
            let isFullscreen = Ax.isFullscreenAttr.getter(values[0]) == true
            return NativeFacts(isFullscreen: isFullscreen, isMinimized: !isFullscreen && Ax.minimizedAttr.getter(values[1]) == true)
        }
        // After an AX timeout, treat fullscreen like a timed-out get (false) instead of waiting for it again
        let isFullscreen = error != .cannotComplete && window.get(Ax.isFullscreenAttr) == true
        return NativeFacts(isFullscreen: isFullscreen, isMinimized: !isFullscreen && window.get(Ax.minimizedAttr) == true)
    }

    /// See ``postPlacements(_:isZoom:)``. The app's animations are off from the batch's first write to its end
    private func place(_ placements: [Placement], _ generations: [UInt64], isZoom: Bool) {
        let animations = AnimationsOff(element)
        defer { animations.restore() }
        for (placement, generation) in zip(placements, generations) {
            let windowId = placement.windowId.raw
            if let ax = windows[windowId]?.ax {
                let window = AxPlacementWindow(ax: ax, animations: animations) { @Sendable [self] in
                    self.generations.withLock { $0.isLatest(windowId, generation) } &&
                        !isTerminating.load(ordering: .sequentiallyConsistent)
                }
                windows[windowId]?.placement.apply(placement, to: window, isZoom: isZoom)
            }
            self.generations.withLock { $0.finish(windowId, generation) }
        }
    }

    /// `layout tiling` and `enable on`, see ``PlacementState/rememberFloatingSize(of:)``
    func rememberFloatingSize(_ windowId: UInt32) {
        guard let ax = windows[windowId]?.ax else { return }
        // It only reads: the animations stay on
        windows[windowId]?.placement.rememberFloatingSize(of: AxPlacementWindow(ax: ax, animations: AnimationsOff(element)) { @Sendable in
            !isTerminating.load(ordering: .sequentiallyConsistent)
        })
    }

    /// `layout floating`, see ``PlacementState/restoreFloatingSize(to:)``
    func restoreFloatingSize(_ windowId: UInt32) {
        guard let window = windows[windowId] else { return }
        let animations = AnimationsOff(element)
        defer { animations.restore() }
        window.placement.restoreFloatingSize(to: AxPlacementWindow(ax: window.ax, animations: animations) { @Sendable in
            !isTerminating.load(ordering: .sequentiallyConsistent)
        })
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

    /// Presses the window's close button. On success, unregisters the window
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

/// The resume-once box of ``AxApp/call(_:)``: the body's result or the caller's cancellation, whichever comes first,
/// resumes the caller
nonisolated private final class CallBox<T: Sendable>: Sendable {
    typealias Continuation = CheckedContinuation<Result<T, CancellationError>, Never>
    private enum State {
        case starting // The caller hasn't suspended yet
        case suspended(Continuation)
        case resolvedEarly(Result<T, CancellationError>) // Resolved before the caller suspended: it resumes itself
        case resumed
    }

    private let state: Mutex<State> = Mutex(.starting)

    var isResolved: Bool {
        state.withLock { state in
            switch state {
                case .starting, .suspended: false
                case .resolvedEarly, .resumed: true
            }
        }
    }

    func suspend(_ continuation: Continuation) {
        let early: Result<T, CancellationError>? = state.withLock { state in
            guard case .resolvedEarly(let result) = state else {
                state = .suspended(continuation)
                return nil
            }
            state = .resumed
            return result
        }
        if let early {
            continuation.resume(returning: early)
        }
    }

    /// The first call wins
    func resolve(_ result: Result<T, CancellationError>) {
        let continuation: Continuation? = state.withLock { state in
            switch state {
                case .starting:
                    state = .resolvedEarly(result)
                    return nil
                case .suspended(let continuation):
                    state = .resumed
                    return continuation
                case .resolvedEarly, .resumed:
                    return nil
            }
        }
        continuation?.resume(returning: result)
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
    // No strong reference, not even a temporary one (P8): if it were the last one, the isolated deinit would run inline,
    // inside this AXObserver callout, and release the observer whose callout is on the stack. Without it, the last
    // release happens elsewhere, and the deinit runs as a job after the callout
    let pid = unsafe Unmanaged<AxApp>.fromOpaque(refcon)._withUnsafeGuaranteedRef { app in
        app.preconditionIsolated() // P1: traps on another thread
        return app.pid
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
        await world.sessions.onAxEvent(pid: pid, event)
    }
}

nonisolated private func axRect(_ window: AXUIElement) -> Rect? {
    guard let topLeftCorner = window.get(Ax.topLeftCornerAttr) else { return nil }
    guard let size = window.get(Ax.sizeAttr) else { return nil }
    return Rect(topLeftX: topLeftCorner.x, topLeftY: topLeftCorner.y, width: size.width, height: size.height)
}

/// A window of the app for ``PlacementState``, on the app's thread
nonisolated private struct AxPlacementWindow: PlacementWindow {
    let ax: AXUIElement
    let animations: AnimationsOff
    let isCurrentNow: @Sendable () -> Bool

    func isCurrent() -> Bool { isCurrentNow() }
    func topLeft() -> CGPoint? { ax.get(Ax.topLeftCornerAttr) }
    func size() -> CGSize? { ax.get(Ax.sizeAttr) }

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
