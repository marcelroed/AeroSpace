import AppKit
import Common
import OrderedCollections

private let disclaimer =
    """
    !!! DISCLAIMER !!!
    !!! 'debug-windows' command is not stable API. Please don't rely on the command existence and output format !!!
    !!! The only intended use case is to report bugs about incorrect windows handling !!!
    """

private var debugWindowsState: DebugWindowsState = .notRecording
private var debugWindowsLog: OrderedDictionary<UInt32, String> = [:]
private let debugWindowsLimit = 10

enum DebugWindowsState {
    case recording
    case notRecording
    case recordingAborted
}

struct DebugWindowsCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var windowId: UInt32? = nil

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
        switch debugWindowsState {
            case .recording:
                debugWindowsState = .notRecording
                cx.out(debugWindowsLog.values.joined(separator: "\n\n"))
                cx.out("\n" + disclaimer + "\n")
                cx.out("Debug session finished" + "\n")
                debugWindowsLog = [:]
            case .notRecording:
                let target = try cx.target()
                debugWindowsState = .recording
                debugWindowsLog = [:]
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
            case .recordingAborted:
                cx.out(
                    """
                    Recording of the previous session was aborted after \(debugWindowsLimit) windows has been focused
                    Run the command one more time to start new debug session
                    """,
                )
                debugWindowsState = .notRecording
                debugWindowsLog = [:]
                throw .silent
        }
    }
}

private func dumpWindowDebugInfo(_ window: Window, _ cm: CancellationMode) async throws -> String {
    let window = window.asMacWindow()
    let appInfoDic = window.macApp.nsApp.bundleURL.flatMap { Bundle.init(url: $0) }?.infoDictionary ?? [:]

    var result: OrderedJson.JsonDict = try await window.macApp.dumpWindowAxInfo(windowId: window.windowId, cm)

    let windowLevel = getWindowLevel(for: window.windowId)
    let windowLevelJson = windowLevel?.toJson() ?? .null
    result["Aero.windowLevel"] = windowLevelJson
    result["Aero.axWindowId"] = .int(window.windowId)
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

    let isDialog = try await window.macApp.isDialogHeuristic(window.windowId, windowLevel, cm)
    let isWindow = try await window.macApp.isWindowHeuristic(window.windowId, windowLevel, cm)
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
    guard debugWindowsState == .recording else { return }
    if debugWindowsLog.keys.contains(window.windowId) { return }
    if debugWindowsLog.count >= debugWindowsLimit {
        debugWindowsState = .recordingAborted
        debugWindowsLog = [:]
        return
    }
    debugWindowsLog[window.windowId] = try await dumpWindowDebugInfo(window, cm)
}
