import AppKit
import Common

struct FullscreenCommand: Command {
    let args: FullscreenCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let window = args.resolveWindowOrReportError(env, io) else { return .fail }
        let newState = args.toggle.resolve(current: window.isFullscreen)
        if newState == window.isFullscreen {
            return .noop(io, failIfNoop: args.failIfNoop, newState
                ? "Already fullscreen. Tip: use --fail-if-noop to exit with non-zero code"
                : "Already not fullscreen. Tip: use --fail-if-noop to exit with non-zero code")
        }
        window.isFullscreen = newState
        window.noOuterGapsInFullscreen = args.noOuterGaps

        // Focus on its own workspace
        window.markAsMostRecentChild()
        return .succ
    }
}

let noWindowIsFocused = "No window is focused"
