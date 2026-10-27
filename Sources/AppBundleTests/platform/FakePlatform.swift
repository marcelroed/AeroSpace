@testable import AppBundle
import AppKit
import Common

/// The ``Platform`` of the tests: macOS as plain state. Reads return without suspending, effects apply at once, and
/// every call goes into ``calls`` for the tests that count AX work per scenario
final class FakePlatform: Platform {
    /// What ``monitors()`` returns. A stored `monitors` would clash with the protocol's method
    var monitorInfos: [MonitorInfo] = [testMonitor]
    var apps: [AppInfo] = [testApp]
    var windows: [WindowId: FakeWindow] = [:]
    /// The window with the native focus
    var focused: WindowId? = nil
    /// false: the app is hung or terminated. Its reads return nil, and its windows aren't listed
    var answers: [pid_t: Bool] = [:]
    var hiddenApps: Set<pid_t> = []
    var isLeftMouseDown: Bool = false
    var mouseLocation: CGPoint = .zero
    private(set) var calls: [PlatformCall] = []

    func calls(of kind: PlatformCall.Kind, _ id: WindowId? = nil) -> [PlatformCall] {
        calls.filter { $0.kind == kind && (id == nil || $0.windowId == id) }
    }

    func resetCalls() { calls = [] }

    // MARK: Snapshot reads

    func monitors() -> [MonitorInfo] { monitorInfos }
    var hasScreens: Bool { !monitorInfos.isEmpty }
    func runningApps() -> [AppInfo] { apps }
    func isHidden(_ app: AppInfo) -> Bool { hiddenApps.contains(app.pid) }
    var counters: [String: Int] { [:] }

    // MARK: Observe reads

    func listWindows() -> [AppInfo: [WindowId]] {
        calls.append(.listWindows)
        var result: [AppInfo: [WindowId]] = [:]
        for app in apps where answers[app.pid] != false {
            result[app] = windows.filter { $0.value.app == app }.keys.sorted()
        }
        return result
    }

    func focusedWindow() -> FocusedWindow? {
        calls.append(.focusedWindow)
        return focused.flatMap { id in answering(id).map { FocusedWindow(app: $0.app, windowId: id) } }
    }

    func classify(_ id: WindowId) -> AxUiElementWindowType? { read(.classify(id), id)?.kind }
    func nativeFacts(_ id: WindowId) -> NativeFacts? { read(.nativeFacts(id), id)?.facts }
    func observedRect(_ id: WindowId) -> Rect? { read(.observedRect(id), id)?.rect }

    // MARK: Single reads

    func rect(_ id: WindowId) -> Rect? { read(.rect(id), id)?.rect }
    func title(_ id: WindowId) -> String? { read(.title(id), id)?.title }
    func facts(_ id: WindowId) -> NativeFacts? { read(.facts(id), id)?.facts }
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
                case .frame(let id, let topLeft, let size):
                    calls.append(.frame(id, topLeft: topLeft, size: size))
                    windows[id]?.frames.append(AxFrame(topLeft: topLeft, size: size))
                    windows[id]?.parked = nil
                case .park(let id, let target):
                    calls.append(.park(id, target))
                    windows[id]?.parked = target
            }
        }
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
        calls.append(call)
        return answering(id)
    }
}

/// The app of the test windows, unless a test makes others
let testApp = AppInfo(pid: 0, bundleId: "bobko.AeroSpace.test-app", name: "bobko.AeroSpace.test-app", execPath: nil, bundlePath: nil)

struct FakeWindow {
    var app: AppInfo
    /// What AX reports as the window's frame
    var rect: Rect?
    var kind: AxUiElementWindowType = .window
    var isFullscreen = false
    var isMinimized = false
    var title: String
    /// The frame writes, in order
    var frames: [AxFrame] = []
    var parked: ParkTarget? = nil

    var facts: NativeFacts { NativeFacts(isFullscreen: isFullscreen, isMinimized: !isFullscreen && isMinimized) }
}

// periphery:ignore - false positive unused warning. The properties are read by the synthesized Equatable
struct AxFrame: Equatable {
    let topLeft: CGPoint?
    let size: CGSize?
}

/// A call of ``FakePlatform``
enum PlatformCall: Equatable {
    case listWindows, focusedWindow
    case classify(WindowId), nativeFacts(WindowId), observedRect(WindowId)
    case rect(WindowId), title(WindowId), facts(WindowId), kind(WindowId), windowCount(pid_t), debugInfo(WindowId)
    case frame(WindowId, topLeft: CGPoint?, size: CGSize?), park(WindowId, ParkTarget)
    case focus(WindowId), close(WindowId), setNative(WindowId, NativeChange), unhideApp(pid_t), quit(pid_t)

    enum Kind: Equatable {
        case listWindows, focusedWindow, classify, nativeFacts, observedRect
        case rect, title, facts, kind, windowCount, debugInfo
        case frame, park, focus, close, setNative, unhideApp, quit
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
            case .frame: .frame
            case .park: .park
            case .focus: .focus
            case .close: .close
            case .setNative: .setNative
            case .unhideApp: .unhideApp
            case .quit: .quit
        }
    }

    var windowId: WindowId? {
        switch self {
            case .classify(let id), .nativeFacts(let id), .observedRect(let id), .rect(let id), .title(let id), .facts(let id),
                 .kind(let id), .debugInfo(let id), .frame(let id, _, _), .park(let id, _), .focus(let id), .close(let id),
                 .setNative(let id, _):
                id
            case .listWindows, .focusedWindow, .windowCount, .unhideApp, .quit: nil
        }
    }
}
