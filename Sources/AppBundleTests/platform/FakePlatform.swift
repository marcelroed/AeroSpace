@testable import AppBundle
import AppKit
import Common

/// The ``Platform`` of the tests: macOS as plain state. Reads return without suspending (unless a test holds them with a
/// ``Gate``), effects apply at once, and
/// every call goes into ``calls`` for the tests that count AX work per scenario. The placements run AxApp's code
/// (``PlacementState``) against ``FakeWindow/rect``
final class FakePlatform: Platform {
    /// What ``monitors()`` returns. A stored `monitors` would clash with the protocol's method
    var monitorInfos: [MonitorInfo] = [testMonitor]
    var apps: [AppInfo] = [testApp]
    var windows: [WindowId: FakeWindow] = [:]
    /// The window with the native focus
    var focused: WindowId? = nil
    /// false: the app is hung. ``listWindows()`` reports it as `.noAnswer`, and its windows' reads return nil
    var answers: [pid_t: Bool] = [:]
    var hiddenApps: Set<pid_t> = []
    var isLeftMouseDown: Bool = false
    var mouseLocation: CGPoint = .zero
    /// Every call in order, and the AX reads and frame writes of the placements. The frame writes are only here: a
    /// per-window copy cost as much as the layout itself in the perf benchmarks (perf/cand-m2-plat)
    private(set) var calls: [PlatformCall] = []
    /// Called after each read: the scenario tests change macOS or cancel the session there, as if it happened during the
    /// read
    var onRead: ((PlatformCall) -> ())? = nil
    /// Awaited before each title read: a ``Gate`` there holds a callback's title matcher, as a busy app does
    var beforeTitle: ((WindowId) async -> ())? = nil
    /// Awaited before an app lists its windows: a ``Gate`` there makes the app miss its listing deadline
    var beforeListing: ((AppInfo) async -> ())? = nil
    /// LivePlatform's listing deadlines, for the tests that hold an app in `beforeListing`. nil: every listing is awaited
    var listingDeadlines: ListingDeadlines? = nil

    func calls(of kind: PlatformCall.Kind, _ id: WindowId? = nil) -> [PlatformCall] {
        calls.filter { $0.kind == kind && (id == nil || $0.windowId == id) }
    }

    /// The frame writes of the window since the last ``resetCalls()``, in order
    func frames(of id: WindowId) -> [AxFrame] {
        calls.compactMap { if case .frame(id, let topLeft, let size) = $0 { AxFrame(topLeft: topLeft, size: size) } else { nil } }
    }

    func resetCalls() { calls = [] }

    func isParked(_ id: WindowId) -> Bool { windows[id]?.placement.isParked == true }

    // MARK: Snapshot reads

    func monitors() -> [MonitorInfo] { monitorInfos }
    var hasScreens: Bool { !monitorInfos.isEmpty }
    func runningApps() -> [AppInfo] { apps }
    func isHidden(_ app: AppInfo) -> Bool { hiddenApps.contains(app.pid) }
    var counters: [String: Int] { [:] }

    // MARK: Observe reads

    /// Each app lists its windows in the order of their ids
    func listWindows(waitingForEveryApp: Bool) async throws(CancellationError) -> [AppWindows] {
        defer { logRead(.listWindows) }
        var result: [AppWindows] = []
        for app in apps {
            let list = { [self] () async throws(CancellationError) -> [WindowId]? in
                await beforeListing?(app)
                return answers[app.pid] == false ? nil : windows.filter { $0.value.app == app }.keys.sorted()
            }
            let ids = if let listingDeadlines {
                try await listingDeadlines.list(app.pid, hasDeadline: !waitingForEveryApp, list)
            } else {
                try await list()
            }
            result.append(ids.map { .listed(app, $0) } ?? .noAnswer(app))
        }
        return result
    }

    func focusedWindow() -> FocusedWindow? {
        defer { logRead(.focusedWindow) }
        return focused.flatMap { id in answering(id).map { FocusedWindow(app: $0.app, windowId: id) } }
    }

    func classify(_ windows: [AppInfo: [WindowId]]) -> [WindowId: DetectedWindow] {
        let ids = windows.values.flatMap(\.self).sorted()
        defer { logRead(.classify(ids)) }
        return ids.reduce(into: [:]) { result, id in
            if let window = answering(id), let kind = window.kind {
                result[id] = DetectedWindow(kind: kind, rect: window.rect, level: window.level)
            }
        }
    }

    func nativeFacts(_ windows: [AppInfo: [WindowId]]) -> [WindowId: NativeFacts] {
        let ids = windows.values.flatMap(\.self).sorted()
        defer { logRead(.nativeFacts(ids)) }
        return ids.reduce(into: [:]) { result, id in result[id] = answering(id)?.facts }
    }

    func debugInfos(_ windows: [AppInfo: [WindowId]]) -> [WindowId: WindowDebugInfo] {
        windows.values.flatMap(\.self).reduce(into: [:]) { result, id in result[id] = debugInfo(id) }
    }

    func observedRect(_ id: WindowId) -> Rect? { read(.observedRect(id), id)?.rect }

    // MARK: Single reads

    func rect(_ id: WindowId) -> Rect? { read(.rect(id), id)?.rect }
    func title(_ id: WindowId) async -> String? {
        await beforeTitle?(id)
        return read(.title(id), id)?.title
    }
    func facts(_ id: WindowId) -> NativeFactsRead {
        defer { logRead(.facts(id)) }
        guard let window = windows[id] else { return .closed }
        return answers[window.app.pid] == false ? .noAnswer : .facts(window.facts)
    }
    func kind(_ id: WindowId) -> AxUiElementWindowType? { read(.kind(id), id)?.kind }

    func windowCount(_ app: AppInfo) -> Int? {
        calls.append(.windowCount(app.pid))
        return answers[app.pid] == false ? nil : windows.values.count { $0.app == app }
    }

    func debugInfo(_ id: WindowId) -> WindowDebugInfo? {
        guard read(.debugInfo(id), id) != nil else { return nil }
        return WindowDebugInfo(
            axWindow: [:], axApp: [:], windowLevel: nil, appVersionShort: nil, appVersion: nil, activationPolicy: "regular",
            execUrl: nil, bundleUrl: nil, isDialog: false, isWindow: true,
        )
    }

    // MARK: Effects

    func apply(_ batch: [Placement]) {
        for placement in batch {
            switch placement {
                case .frame: break // Its write is the log entry
                case .floating(let id, let target): calls.append(.floating(id, target))
                case .park(let id, let target): calls.append(.park(id, target))
                case .leave(let id): calls.append(.leave(id))
            }
            let id = placement.windowId
            guard let window = windows[id] else { continue }
            let isZoom = window.app.bundleId == KnownBundleId.zoom.rawValue
            window.placement.apply(placement, to: FakeAxWindow(id: id, window: window, platform: self), isZoom: isZoom)
        }
    }

    func rememberFloatingSize(_ id: WindowId) {
        calls.append(.rememberFloatingSize(id))
        windows[id]?.placement.rememberFloatingSize(of: FakeAxWindow(id: id, window: windows[id], platform: self))
    }

    func restoreFloatingSize(_ id: WindowId) {
        calls.append(.restoreFloatingSize(id))
        windows[id]?.placement.restoreFloatingSize(to: FakeAxWindow(id: id, window: windows[id], platform: self))
    }

    func focus(_ id: WindowId) {
        calls.append(.focus(id))
        if windows[id] != nil { focused = id }
    }

    func close(_ id: WindowId) {
        calls.append(.close(id))
        windows[id] = nil
        if focused == id { focused = nil }
    }

    func setNative(_ id: WindowId, _ change: NativeChange) {
        calls.append(.setNative(id, change))
        switch change {
            case .fullscreen(let value): windows[id]?.isFullscreen = value
            case .minimized(let value): windows[id]?.isMinimized = value
        }
    }

    func unhideApp(_ app: AppInfo) {
        calls.append(.unhideApp(app.pid))
        hiddenApps.remove(app.pid)
    }

    func quit(_ app: AppInfo) -> Bool {
        calls.append(.quit(app.pid))
        windows = windows.filter { $0.value.app != app }
        return true
    }

    nonisolated func restoreForTermination() {}

    private func answering(_ id: WindowId) -> FakeWindow? {
        windows[id].flatMap { answers[$0.app.pid] == false ? nil : $0 }
    }

    private func read(_ call: PlatformCall, _ id: WindowId) -> FakeWindow? {
        defer { logRead(call) }
        return answering(id)
    }

    fileprivate func log(_ call: PlatformCall) { calls.append(call) }

    private func logRead(_ call: PlatformCall) {
        calls.append(call)
        onRead?(call)
    }
}

/// A window of ``FakePlatform`` for ``PlacementState``: each AX read and frame write goes into the call log, and the
/// writes move the window
private struct FakeAxWindow: @MainActor PlacementWindow {
    let id: WindowId
    let window: FakeWindow?
    let platform: FakePlatform

    func isCurrent() -> Bool { true }

    func topLeft() -> CGPoint? {
        platform.log(.axRead(id))
        return window?.rect?.topLeftCorner
    }

    func size() -> CGSize? {
        platform.log(.axRead(id))
        return window?.rect?.size
    }

    @discardableResult
    func setFrame(topLeft: CGPoint?, size: CGSize?) -> Bool {
        platform.log(.frame(id, topLeft: topLeft, size: size))
        if let rect = window?.rect {
            window?.rect = Rect(
                topLeftX: topLeft?.x ?? rect.topLeftX,
                topLeftY: topLeft?.y ?? rect.topLeftY,
                width: size?.width ?? rect.width,
                height: size?.height ?? rect.height,
            )
        }
        return topLeft != nil
    }
}

/// The app of the test windows, unless a test makes others
let testApp = AppInfo(pid: 0, bundleId: "bobko.AeroSpace.test-app", name: "bobko.AeroSpace.test-app", execPath: nil, bundlePath: nil)

/// A class: the placements change it in place
final class FakeWindow {
    let app: AppInfo
    /// What AX reports as the window's frame. The frame writes change it
    var rect: Rect?
    /// nil: AX can't tell, as for an off-screen window whose kind depends on its level
    var kind: AxUiElementWindowType? = .window
    /// nil: the window is off-screen
    var level: MacOsWindowLevel? = .normalWindow
    var isFullscreen = false
    var isMinimized = false
    let title: String
    /// AxApp's state of the window. It's registered with its size now
    var placement: PlacementState

    init(app: AppInfo, rect: Rect?, title: String) {
        self.app = app
        self.rect = rect
        self.title = title
        placement = PlacementState(lastFloatingSize: rect?.size)
    }

    var facts: NativeFacts { NativeFacts(isFullscreen: isFullscreen, isMinimized: !isFullscreen && isMinimized) }
}

/// Holds whoever calls ``wait()`` until ``open()``. ``untilWaiting()`` lets the test go on once a session is held
final class Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<(), Never>] = []
    private var watchers: [CheckedContinuation<(), Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiter in
            waiters.append(waiter)
            for watcher in watchers { watcher.resume() }
            watchers = []
        }
    }

    func untilWaiting() async {
        if !waiters.isEmpty { return }
        await withCheckedContinuation { watchers.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}

// periphery:ignore - false positive unused warning. The properties are read by the synthesized Equatable
struct AxFrame: Equatable {
    let topLeft: CGPoint?
    let size: CGSize?
}

/// A call of ``FakePlatform``
enum PlatformCall: Equatable {
    case listWindows, focusedWindow
    case classify([WindowId]), nativeFacts([WindowId]), observedRect(WindowId)
    case rect(WindowId), title(WindowId), facts(WindowId), kind(WindowId), windowCount(pid_t), debugInfo(WindowId)
    /// The placements but `.frame`, whose frame write is its entry
    case floating(WindowId, FloatingTarget), park(WindowId, ParkTarget), leave(WindowId)
    /// What the placements do: one AX attribute read, a frame write (size, position, size: up to 3 AX writes)
    case axRead(WindowId), frame(WindowId, topLeft: CGPoint?, size: CGSize?)
    case rememberFloatingSize(WindowId), restoreFloatingSize(WindowId)
    case focus(WindowId), close(WindowId), setNative(WindowId, NativeChange), unhideApp(pid_t), quit(pid_t)

    enum Kind: Equatable {
        case listWindows, focusedWindow, classify, nativeFacts, observedRect
        case rect, title, facts, kind, windowCount, debugInfo
        case floating, park, leave, axRead, frame, rememberFloatingSize, restoreFloatingSize
        case focus, close, setNative, unhideApp, quit
    }

    var kind: Kind {
        switch self {
            case .listWindows: .listWindows
            case .focusedWindow: .focusedWindow
            case .classify: .classify
            case .nativeFacts: .nativeFacts
            case .observedRect: .observedRect
            case .rect: .rect
            case .title: .title
            case .facts: .facts
            case .kind: .kind
            case .windowCount: .windowCount
            case .debugInfo: .debugInfo
            case .floating: .floating
            case .park: .park
            case .leave: .leave
            case .axRead: .axRead
            case .frame: .frame
            case .rememberFloatingSize: .rememberFloatingSize
            case .restoreFloatingSize: .restoreFloatingSize
            case .focus: .focus
            case .close: .close
            case .setNative: .setNative
            case .unhideApp: .unhideApp
            case .quit: .quit
        }
    }

    /// nil for the batch reads. They log their windows sorted
    var windowId: WindowId? {
        switch self {
            case .observedRect(let id), .rect(let id), .title(let id), .facts(let id), .kind(let id), .debugInfo(let id),
                 .floating(let id, _), .park(let id, _), .leave(let id), .axRead(let id), .frame(let id, _, _),
                 .rememberFloatingSize(let id), .restoreFloatingSize(let id), .focus(let id), .close(let id), .setNative(let id, _):
                id
            case .listWindows, .focusedWindow, .classify, .nativeFacts, .windowCount, .unhideApp, .quit: nil
        }
    }
}
