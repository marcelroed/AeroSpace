import AppKit
import Common

/// Problem ID-B6E178F2: It's not first-class citizen command in AeroSpace model, since it interacts with macOS API directly.
/// Consecutive macos-native-fullscreen commands may not works as expected (because macOS may report correct state with a
/// delay), or may flicker
///
/// The same applies to macos-native-minimize command
struct MacosNativeFullscreenCommand: Command {
    let args: MacosNativeFullscreenCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        guard let window = args.resolveWindowOrReportError(env, io) else { return .fail }
        guard let prevState = try? await window.isMacosFullscreen(.nonCancellable) else { return .fail(io.err(bugPrompt())) }
        let newState = args.toggle.resolve(current: prevState)
        if newState == prevState {
            return .noop(io, failIfNoop: args.failIfNoop, (newState ? "Already fullscreen. " : "Already not fullscreen. ") +
                "Tip: use --fail-if-noop to exit with non-zero code")
        }
        window.asMacWindow().setNativeFullscreen(newState)
        guard let workspace = window.nodeWorkspace else {
            return .fail(io.err(windowIsntPartOfTree(window)))
        }
        if newState { // Enter fullscreen
            window.bind(to: workspace.macOsNativeFullscreenWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        } else { // Exit fullscreen
            do {
                if case .macos(let prevParentKind) = window.layoutReason {
                    try await exitMacOsNativeUnconventionalState(
                        window: window,
                        prevParentKind: prevParentKind,
                        workspace: workspace,
                        .nonCancellable,
                    )
                } else {
                    try await window.relayoutWindow(on: workspace, .nonCancellable)
                }
            } catch {
                return .fail(io.err(bugPrompt()))
            }
        }
        return .succ
    }
}
