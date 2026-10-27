import AppKit
import Common
import ISSoundAdditions
import OrderedCollections

private let disclaimer =
    """
    !!! DISCLAIMER !!!
    !!! 'debug-windows' command is not stable API. Please don't rely on the command existence and output format !!!
    !!! The only intended use case is to report bugs about incorrect windows handling !!!
    """

private let debugWindowsLimit = 10

/// `debug-windows` without `--window-id` records the windows that get focused until it runs again
enum DebugWindowsRecording {
    case off
    case recording(DebugWindowsLog)
    /// More than `debugWindowsLimit` windows got focused
    case aborted
}

/// The dumps of the windows focused during one recording, in focus order. A class, so that a dump awaited during a
/// recording goes into that recording's log, and never into a later recording's
final class DebugWindowsLog {
    var dumps: OrderedDictionary<WindowId, String> = [:]
}

struct DebugWindowsCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var windowId: WindowId? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var result = Self()
        while let option = try a.nextOption() {
            switch option {
                case "--window-id": result.windowId = try a.windowId(of: option)
                default: throw .unknownOption(option)
            }
        }
        try a.end()
        return result
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        if let windowId {
            guard let window = Window.get(byId: windowId) else {
                throw "Can't find window with the specified window-id: \(windowId)"
            }
            guard let a = try? await dumpWindowDebugInfo(window, .nonCancellable) else { throw CmdFail(bugPrompt()) }
            cx.out(a + "\n")
            cx.out(disclaimer)
            return
        }
        switch world.debugWindows {
            case .recording(let log):
                world.debugWindows = .off
                cx.out(log.dumps.values.joined(separator: "\n\n"))
                cx.out("\n" + disclaimer + "\n")
                cx.out("Debug session finished" + "\n")
            case .off:
                let target = try cx.target()
                world.debugWindows = .recording(DebugWindowsLog())
                cx.out(
                    """
                    Debug windows session has started
                    1. Focus the problematic window
                    2. Run 'aerospace debug-windows' once again to finish the session and get the results
                    """,
                )
                // Make sure that the Terminal window that started the recording is recorded first
                if let window = target.windowOrNil {
                    do {
                        try await debugWindowsIfRecording(window, .nonCancellable)
                    } catch {
                        throw CmdFail(bugPrompt(String(describing: error)))
                    }
                }
            case .aborted:
                cx.out(
                    """
                    Recording of the previous session was aborted after \(debugWindowsLimit) windows has been focused
                    Run the command one more time to start new debug session
                    """,
                )
                world.debugWindows = .off
                throw .silent
        }
    }
}

private func dumpWindowDebugInfo(_ window: Window, _ cm: CancellationMode) async throws -> String {
    let window = window.asMacWindow()
    let appInfoDic: [String: Any] = window.macApp.nsApp.bundleURL.flatMap { Bundle(url: $0) }?.infoDictionary ?? [:]

    var result: OrderedJson.JsonDict = try await window.macApp.dumpWindowAxInfo(windowId: window.windowId.raw, cm)

    let windowLevel = getWindowLevel(for: window.windowId)
    let windowLevelJson = windowLevel?.toJson() ?? .null
    result["Aero.windowLevel"] = windowLevelJson
    result["Aero.axWindowId"] = .int(window.windowId.raw)
    result["Aero.workspace"] = .stringOrNull(window.nodeWorkspace?.name)
    result["Aero.treeNodeParent"] = .string(String(describing: window.parent))
    result["Aero.macOS.version"] = .string(ProcessInfo().operatingSystemVersionString) // because built-in apps might behave differently depending on the OS version
    result["Aero.App.appBundleId"] = .stringOrNull(window.app.rawAppBundleId)
    result["Aero.App.pid"] = .int(Int(window.app.pid))
    result["Aero.App.versionShort"] = .stringOrNull(appInfoDic["CFBundleShortVersionString"] as? String)
    result["Aero.App.version"] = .stringOrNull(appInfoDic["CFBundleVersion"] as? String)
    result["Aero.App.nsApp.activationPolicy"] = .string(window.macApp.nsApp.activationPolicy.prettyDescription)
    result["Aero.App.nsApp.execPath"] = .stringOrNull(window.macApp.nsApp.executableURL?.description)
    result["Aero.App.nsApp.appBundlePath"] = .stringOrNull(window.macApp.nsApp.bundleURL?.description)
    result["Aero.AXApp"] = .dict(try await window.macApp.dumpAppAxInfo(cm))

    let isDialog = try await window.macApp.isDialogHeuristic(window.windowId.raw, windowLevel, cm)
    let isWindow = try await window.macApp.isWindowHeuristic(window.windowId.raw, windowLevel, cm)
    result["Aero.AxUiElementWindowType"] = .string(AxUiElementWindowType.new(isWindow: isWindow, isDialog: { isDialog }).rawValue)
    result["Aero.AxUiElementWindowType_isDialogHeuristic"] = .bool(isDialog)

    var matchingCallbacks: [OrderedJson] = []
    for callback in config.onWindowDetected where await callback.matches(window) {
        matchingCallbacks.append(callback.debugJson)
    }
    result["Aero.on-window-detected"] = .array(matchingCallbacks)

    return JSONEncoder.aeroSpaceDefault.encodeToString(OrderedJson.dict(result)).prettyDescription
        .prefixLines(with: "\(window.app.rawAppBundleId ?? "nil-bundle-id").\(window.windowId) ||| ")
}

func debugWindowsIfRecording(_ window: Window, _ cm: CancellationMode) async throws {
    try await recordDebugWindow(window.windowId) { try await dumpWindowDebugInfo(window, cm) }
}

/// Adds the window's dump to the running recording, unless the recording has it already
func recordDebugWindow(_ windowId: WindowId, dump: () async throws -> String) async rethrows {
    guard case .recording(let log) = world.debugWindows, !log.dumps.keys.contains(windowId) else { return }
    if log.dumps.count >= debugWindowsLimit {
        world.debugWindows = .aborted
        return
    }
    // If the recording finishes during the await, the dump goes into its log, which nobody reads anymore
    log.dumps[windowId] = try await dump()
}

struct MoveMouseCommand: nonisolated Command {
    nonisolated enum MouseTarget: String, CaseIterable, Sendable {
        case monitorLazyCenter = "monitor-lazy-center"
        case monitorForceCenter = "monitor-force-center"
        case windowLazyCenter = "window-lazy-center"
        case windowForceCenter = "window-force-center"
    }

    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var mouseTarget: MouseTarget
    var failIfNoop = false

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var failIfNoop = false
        while let option = try a.nextOption() {
            switch option {
                case "--fail-if-noop": failIfNoop = true
                default: throw .unknownOption(option)
            }
        }
        let mouseTarget: MouseTarget = try parseEnum(a.positional("<mouse-position>"))
        try a.end()
        if failIfNoop && mouseTarget != .windowLazyCenter && mouseTarget != .monitorLazyCenter {
            throw "--fail-if-noop is only compatible with window-lazy-center or monitor-lazy-center"
        }
        return Self(mouseTarget: mouseTarget, failIfNoop: failIfNoop)
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let mouse = mouseLocation
        let target = try cx.target()
        switch mouseTarget {
            case .windowLazyCenter:
                let rect = try await windowSubjectRect(target)
                if rect.contains(mouse) {
                    return try noop(cx, failIfNoop: failIfNoop, "The mouse already belongs to the window. Tip: use --fail-if-noop to exit with non-zero code")
                }
                try moveMouse(rect.center)
            case .windowForceCenter:
                try await moveMouse(windowSubjectRect(target).center)
            case .monitorLazyCenter:
                let rect = target.workspace.workspaceMonitor.rect
                if rect.contains(mouse) {
                    return try noop(cx, failIfNoop: failIfNoop, "The mouse already belongs to the monitor. Tip: use --fail-if-noop to exit with non-zero code")
                }
                try moveMouse(rect.center)
            case .monitorForceCenter:
                try moveMouse(target.workspace.workspaceMonitor.rect.center)
        }
    }
}

private func moveMouse(_ point: CGPoint) throws(CmdFail) {
    guard let event = CGEvent(
        mouseEventSource: nil,
        mouseType: CGEventType.mouseMoved,
        mouseCursorPosition: point,
        mouseButton: CGMouseButton.left,
    ) else {
        throw "Failed to move mouse"
    }
    event.post(tap: CGEventTapLocation.cghidEventTap)
}

private func windowSubjectRect(_ target: LiveFocus) async throws(CmdFail) -> Rect {
    // todo bug it's bad that we operate on the "ax physical" state directly. command seq won't work correctly
    //      focus <direction> command has the similar problem
    guard let window = target.windowOrNil else { throw CmdFail(noWindowIsFocused) }
    if let rect = window.lastAppliedLayoutPhysicalRect { return rect }
    if let rect = try? await window.getAxRect(.nonCancellable) { return rect }
    throw "Failed to get rect of window '\(window.windowId)'"
}

struct VolumeCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var action: VolumeAction
    var gui = true

    nonisolated enum VolumeAction: Equatable, Sendable {
        case up, down, muteToggle, muteOn, muteOff
        case set(Int)
    }

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var gui = true
        while let option = try a.nextOption() {
            switch option {
                case "--no-gui": gui = false
                default: throw .unknownOption(option)
            }
        }
        let action: VolumeAction = switch try a.positional("(up|down|mute-toggle|mute-on|mute-off|set)") {
            case "up": .up
            case "down": .down
            case "mute-toggle": .muteToggle
            case "mute-on": .muteOn
            case "mute-off": .muteOff
            case "set":
                switch Int(try a.positional("<number>")) {
                    case let int? where (0 ... 100).contains(int): .set(int)
                    default: throw "<number> must be an integer from 0 to 100"
                }
            case let arg: throw "Can't parse '\(arg)'.\nPossible values: (up|down|mute-toggle|mute-on|mute-off|set)"
        }
        try a.end()
        return Self(action: action, gui: gui)
    }

    func run(_ cx: CmdContext) throws(CmdFail) {
        switch action {
            case .up:
                Sound.output.increaseVolume(by: 0.0625, autoMuteUnmute: true)
            case .down:
                Sound.output.decreaseVolume(by: 0.0625, autoMuteUnmute: true)
            case .muteToggle:
                Sound.output.isMuted.toggle()
            case .muteOn:
                Sound.output.isMuted = true
            case .muteOff:
                Sound.output.isMuted = false
            case .set(let int):
                Sound.output.setVolume(Float(int) / 100, autoMuteUnmute: true)
        }
        if gui {
            do {
                let volume: Float = Sound.output.isMuted ? 0 : try Sound.output.readVolume()
                world.ui.volumePanel.update(with: volume)
            } catch {
                throw CmdFail(bugPrompt(String(describing: error)))
            }
        }
    }
}

struct EnableCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var targetState: ToggleEnum
    var failIfNoop = false

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var failIfNoop = false
        while let option = try a.nextOption() {
            switch option {
                case "--fail-if-noop": failIfNoop = true
                default: throw .unknownOption(option)
            }
        }
        let targetState: ToggleEnum = try a.positional()
        try a.end()
        if targetState == .toggle && failIfNoop { throw "--fail-if-noop is incompatible with 'toggle' argument" }
        return Self(targetState: targetState, failIfNoop: failIfNoop)
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let prevState = world.isEnabled
        let newState = targetState.resolve(current: prevState)
        if newState == prevState {
            return try noop(cx, failIfNoop: failIfNoop, newState
                ? "Already enabled. Tip: use --fail-if-noop to exit with non-zero code"
                : "Already disabled. Tip: use --fail-if-noop to exit with non-zero code")
        }
        // No screens (e.g., during display reconfiguration). Disabling unhides the windows of all workspaces in the layout,
        // which waits for the screens, and no session lays them out while AeroSpace is disabled
        if !newState && !world.monitors.hasScreens { throw "Can't disable \(aeroSpaceAppName) while there are no screens" }
        world.isEnabled = newState
        if newState {
            for workspace in Workspace.all {
                for window in workspace.allLeafWindowsRecursive where window.isFloating {
                    window.lastFloatingSize = (try? await window.getAxSize(.nonCancellable)) ?? window.lastFloatingSize
                }
            }
            await activateMode_nonCancellable(mainModeId)
        } else {
            await activateMode_nonCancellable(nil)
        }
    }
}
