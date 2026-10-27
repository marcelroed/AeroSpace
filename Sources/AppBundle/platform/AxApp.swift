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
        let outcome: FirstOutcome<Result<T, CancellationError>> = FirstOutcome()
        post { app in
            if outcome.isResolved { return } // Cancelled before the body started: skip the AX calls
            if isTerminatingNow() {
                outcome.resolve(.failure(CancellationError()))
            } else {
                let value = body(app) { outcome.isResolved || isTerminatingNow() }
                outcome.resolve(isTerminatingNow() ? .failure(CancellationError()) : .success(value))
            }
        }
        return try await outcome.wait(onCancel: .failure(CancellationError())).get()
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
    /// calls, once it's stale or termination starts. The batch's jobs wait for each other, see ``ShownJobs``
    nonisolated func postPlacements(_ placements: [Placement], _ job: PlacementJob) {
        let generations: [UInt64] = self.generations.withLock { generations in placements.map { generations.bump($0.windowId.raw) } }
        if case .shown(let shownJobs) = job {
            shownJobs.posted()
        }
        post { app in app.place(placements, generations, job) }
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
    /// token, compared without IPC), so only a new element costs an `_AXUIElementGetWindow`, which asks the app. An element
    /// keeps its id while it's registered. nil: not a window (e.g. Finder's desktop)
    private func windowId(of ax: AXUIElement) -> UInt32? {
        windows.first { $0.value.ax == ax }?.key ?? ax.containingWindowId()
    }

    /// The window's next `.frame` placement trusts what it found, see ``PlacementState/recordRead(_:)``
    func rect(_ windowId: UInt32) -> Rect? {
        guard let ax = windows[windowId]?.ax else { return nil }
        let rect = axRect(ax)
        windows[windowId]?.placement.recordRead(rect)
        return rect
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

    /// See ``postPlacements(_:_:)``. The app's animations are off from the job's first write to its end. A shown job ends
    /// once the window server shows the tiles that it unparked
    private func place(_ placements: [Placement], _ generations: [UInt64], _ job: PlacementJob) {
        var unparkedTiles: [UnparkedTile] = []
        let beforeFirstWrite: (() -> Void)? = if case .parks(let shownJobs) = job { shownJobs.wait } else { nil }
        let animations = AnimationsOff(element, beforeFirstWrite: beforeFirstWrite)
        for (placement, generation) in zip(placements, generations) {
            let windowId = placement.windowId.raw
            guard let registered = windows[windowId] else { continue }
            let isCurrent = { @Sendable [self] in
                self.generations.withLock { $0.isLatest(windowId, generation) } && !isTerminatingNow()
            }
            let window = AxPlacementWindow(ax: registered.ax, animations: animations, isCurrentNow: isCurrent)
            // A parked tile: where the window server shows it before the write. Not if it's at its frame already: a park
            // that turned stale before its write left it there
            var shownBefore: CGPoint? = nil
            if case .frame(_, let topLeft, _) = placement, registered.placement.isParked {
                shownBefore = windowServerTopLeft(windowId).flatMap { $0.isWithinAPoint(of: topLeft) ? nil : $0 }
            }
            windows[windowId]?.placement.apply(placement, to: window)
            if let shownBefore, window.didWritePosition {
                unparkedTiles.append(UnparkedTile(windowId: windowId, shownBefore: shownBefore, isCurrent: isCurrent))
            }
        }
        animations.restore()
        if case .shown(let shownJobs) = job {
            waitUntilOnScreen(unparkedTiles, until: min(.now() + onScreenWaitLimit, shownJobs.deadline))
            shownJobs.ended()
        }
        // Only now: the wait drops a tile once its write isn't the latest
        self.generations.withLock { windowGenerations in
            for (placement, generation) in zip(placements, generations) {
                windowGenerations.finish(placement.windowId.raw, generation)
            }
        }
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
        guard let ax = windows[windowId]?.ax else { return }
        let animations = AnimationsOff(element)
        defer { animations.restore() }
        let window = AxPlacementWindow(ax: ax, animations: animations) { @Sendable in !isTerminatingNow() }
        windows[windowId]?.placement.restoreFloatingSize(to: window)
    }

    /// Termination: moves the window to the frame that `monitors` computes from its current rect and last floating size
    func restore(_ windowId: UInt32, _ monitors: TerminationMonitors) {
        guard let registered = windows[windowId] else { return }
        let animations = AnimationsOff(element)
        defer { animations.restore() }
        let window = AxPlacementWindow(ax: registered.ax, animations: animations) { @Sendable in true }
        let frame = monitors.restoreFrame(windowRect: window.rect(), registered.placement.lastFloatingSize)
        window.setFrame(topLeft: frame.topLeft, size: frame.size)
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

/// An app's job of a batch (``LivePlatform/apply(_:)``)
nonisolated enum PlacementJob: Sendable {
    /// The shown workspaces' placements. The job ends once the window server shows the tiles it unparked
    case shown(ShownJobs)
    /// The parks. Before its first write, the job waits for the shown jobs
    case parks(waitingFor: ShownJobs)
}

/// The shown jobs of a batch, which its parks wait for: a window leaves for its corner only once the windows that replace
/// it are on screen, or the desktop shows for a few frames. The apps run their jobs in parallel, so a parks job waits,
/// before its first write, until every shown job has ended or the deadline has passed. A parks job that moves no window
/// (each layout parks every hidden window again) doesn't wait
nonisolated struct ShownJobs: Sendable {
    private let group: DispatchGroup = DispatchGroup()
    /// The parks stop waiting then: a slow or hung app holds the other apps' windows in place only that long
    let deadline: DispatchTime

    /// Every shown job is posted before the parks
    func posted() { group.enter() }

    func ended() { group.leave() }

    func wait() { _ = group.wait(timeout: deadline) }
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

/// A tile that a shown job unparked, which the parks wait for (``waitUntilOnScreen(_:until:windowServerTopLeft:)``)
nonisolated struct UnparkedTile {
    let windowId: UInt32
    /// Where the window server showed the window before the write, usually its corner
    let shownBefore: CGPoint
    /// false once a newer write of the window is posted or termination started: nobody waits for this write then
    let isCurrent: () -> Bool
}

/// An app can answer the AX writes of a window before it moves the window on screen: cmux moves it ~25 ms later. The parks
/// that wait for the shown job (``ShownJobs``) would uncover the desktop in between, so the job waits until the window
/// server shows each tile it unparked away from where it was, until `deadline`. Away is enough: the app's animations are
/// off (``AnimationsOff``), so the move is a jump to where the app puts the window, which may be a bit off the target
nonisolated func waitUntilOnScreen(
    _ tiles: [UnparkedTile],
    until deadline: DispatchTime,
    windowServerTopLeft: (UInt32) -> CGPoint? = windowServerTopLeft,
) {
    var pending = tiles
    while true {
        pending.removeAll { tile in
            guard tile.isCurrent(), let shown = windowServerTopLeft(tile.windowId) else { return true } // Or it closed
            return shown != tile.shownBefore
        }
        if pending.isEmpty || DispatchTime.now() >= deadline { return }
        Thread.sleep(forTimeInterval: 0.001)
    }
}

/// From the shown job's last write. The parks' deadline cuts it short (see ``LivePlatform``'s `parkWaitLimit`)
nonisolated private let onScreenWaitLimit: DispatchTimeInterval = .milliseconds(100)

/// The window's top left corner as the window server shows it. nil once the window is gone
nonisolated private func windowServerTopLeft(_ windowId: UInt32) -> CGPoint? {
    guard let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, windowId) as? [NSDictionary])?.first,
          let bounds = info[kCGWindowBounds] as? NSDictionary,
          let rect = CGRect(dictionaryRepresentation: bounds)
    else { return nil }
    return rect.origin
}

nonisolated extension CGPoint {
    /// AX and the window server give whole points, and the layout's frames have fractions
    fileprivate func isWithinAPoint(of other: CGPoint) -> Bool { abs(x - other.x) < 1 && abs(y - other.y) < 1 }
}

/// A window of the app for ``PlacementState``, on the app's thread
nonisolated private final class AxPlacementWindow: PlacementWindow {
    let ax: AXUIElement
    let animations: AnimationsOff
    let isCurrentNow: @Sendable () -> Bool
    /// Whether the app took the last position write. `setFrame`'s result says only that the write was sent: a window
    /// that refuses it, an AX timeout and `--read-only` don't move
    private(set) var didWritePosition = false

    init(ax: AXUIElement, animations: AnimationsOff, isCurrentNow: @escaping @Sendable () -> Bool) {
        self.ax = ax
        self.animations = animations
        self.isCurrentNow = isCurrentNow
    }

    func isCurrent() -> Bool { isCurrentNow() }
    func rect() -> Rect? { axRect(ax) }

    @discardableResult
    func setFrame(topLeft: CGPoint?, size: CGSize?) -> Bool {
        guard isCurrent() else { return false }
        animations.turnOff()
        guard isCurrent() else { return false } // A park's first write waited for the shown jobs
        // Set size and then the position. The order is important https://github.com/nikitabobko/AeroSpace/issues/143
        //                                                        https://github.com/nikitabobko/AeroSpace/issues/335
        if let size { ax.set(Ax.sizeAttr, size) }
        guard isCurrent(), let topLeft else { return false }
        didWritePosition = ax.set(Ax.topLeftCornerAttr, topLeft)
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
    /// Runs once, before the first write and before the animations go off: a parks job waits there for the shown jobs,
    /// so that a parks job that moves no window doesn't wait
    private let beforeFirstWrite: (() -> Void)?
    /// nil until the first write
    private var wasEnabled: Bool? = nil

    init(_ app: AXUIElement, beforeFirstWrite: (() -> Void)? = nil) {
        self.app = app
        self.beforeFirstWrite = beforeFirstWrite
    }

    func turnOff() {
        if wasEnabled != nil { return }
        beforeFirstWrite?()
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
