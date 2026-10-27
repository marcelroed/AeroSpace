import AppKit
import Common

struct RunCallbackCommand: nonisolated Command {
    nonisolated enum CallbackKind: String, CaseIterable, Equatable, Sendable {
        case onWindowDetected = "on-window-detected"
        case onFocusChanged = "on-focus-changed"
        case onFocusedMonitorChanged = "on-focused-monitor-changed"
    }

    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var callback: CallbackKind
    var forEveryWindow = false
    var windowId: UInt32? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var forEveryWindow = false
        var windowId: UInt32? = nil
        while let option = try a.nextOption() {
            switch option {
                case "--for-every-window": forEveryWindow = true
                case "--window-id": windowId = try a.windowId(of: option)
                default: throw .unknownOption(option)
            }
        }
        let callback: CallbackKind = try parseEnum(a.positional("<callback>"))
        try a.end()
        if forEveryWindow && windowId != nil { throw .conflicting("--for-every-window", "--window-id") }
        if forEveryWindow && callback != .onWindowDetected { throw "--for-every-window is only allowed with 'on-window-detected'" }
        if windowId != nil && callback != .onWindowDetected { throw "--window-id is only allowed with 'on-window-detected'" }
        return Self(callback: callback, forEveryWindow: forEveryWindow, windowId: windowId)
    }

    /// Exits with the exit code of the callback
    func run(_ cx: CmdContext) async throws(CmdFail) {
        let target = try cx.target(windowId: windowId)
        let exitCode: Int32
        switch callback {
            case .onWindowDetected where forEveryWindow:
                exitCode = await onWindowDetected(cx.env, cx.io, forEvery: MacWindow.allWindows)
            case .onWindowDetected:
                guard let window = target.windowOrNil else { throw CmdFail(noWindowIsFocused) }
                exitCode = await onWindowDetected(cx.env, cx.io, window)
            case .onFocusChanged:
                exitCode = await onFocusChanged(cx.env, cx.io, target)
            case .onFocusedMonitorChanged:
                exitCode = await onFocusedMonitorChanged(cx.env, cx.io, target)
        }
        if exitCode != EXIT_CODE_ZERO { throw CmdFail(nil, exitCode: exitCode) }
    }
}

/// `windows` is a parameter because tests can't create a `MacWindow`
func onWindowDetected(_ env: CmdEnv, _ io: CmdIo, forEvery windows: [Window]) async -> Int32 {
    var exitCode = EXIT_CODE_ZERO
    for window in windows.sortedBy({ $0.windowId }) where window.shouldRunOnWindowDetected {
        let windowExitCode = await onWindowDetected(env, io, window)
        if exitCode == EXIT_CODE_ZERO { exitCode = windowExitCode } // Report the first failure
    }
    return exitCode
}
