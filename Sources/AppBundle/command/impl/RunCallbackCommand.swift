import AppKit
import Common

struct RunCallbackCommand: Command {
    let args: RunCallbackCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) async -> Int32ExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        switch args.callback.val {
            case .onWindowDetected where args.forEveryWindow:
                return await onWindowDetected(env, io, forEvery: MacWindow.allWindows)
            case .onWindowDetected:
                guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
                return await onWindowDetected(env, io, window)
            case .onFocusChanged:
                return await onFocusChanged(env, io, target)
            case .onFocusedMonitorChanged:
                return await onFocusedMonitorChanged(env, io, target)
        }
    }
}

/// `windows` is a parameter because tests can't create a `MacWindow`
func onWindowDetected(_ env: CmdEnv, _ io: CmdIo, forEvery windows: [Window]) async -> Int32ExitCode {
    var exitCode = Int32ExitCode.succ
    for window in windows.sortedBy({ $0.windowId }) where window.shouldRunOnWindowDetected {
        let windowExitCode = await onWindowDetected(env, io, window)
        if exitCode == .succ { exitCode = windowExitCode } // Report the first failure
    }
    return exitCode
}
