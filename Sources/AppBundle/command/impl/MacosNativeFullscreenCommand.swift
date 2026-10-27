import AppKit
import Common

/// Problem ID-B6E178F2: It's not first-class citizen command in AeroSpace model, since it interacts with macOS API directly.
/// Consecutive macos-native-fullscreen commands may not works as expected (because macOS may report correct state with a
/// delay), or may flicker
///
/// The same applies to macos-native-minimize command
struct MacosNativeFullscreenCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var toggle: ToggleEnum = .toggle
    var failIfNoop = false
    var windowId: UInt32? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var result = Self()
        while let option = try a.nextOption() {
            switch option {
                case "--fail-if-noop": result.failIfNoop = true
                case "--window-id": result.windowId = try a.windowId(of: option)
                default: throw .unknownOption(option)
            }
        }
        if let onOff: OnOff = try a.positional() { result.toggle = onOff.toggle }
        try a.end()
        if result.failIfNoop && result.toggle == .toggle { throw "--fail-if-noop requires 'on' or 'off' argument" }
        return result
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let window = try cx.window(windowId: windowId)
        guard let prevState = try? await window.isMacosFullscreen(.nonCancellable) else { throw CmdFail(bugPrompt()) }
        let newState = toggle.resolve(current: prevState)
        if newState == prevState {
            return try noop(cx, failIfNoop: failIfNoop, (newState ? "Already fullscreen. " : "Already not fullscreen. ") +
                "Tip: use --fail-if-noop to exit with non-zero code")
        }
        window.asMacWindow().setNativeFullscreen(newState)
        guard let workspace = window.nodeWorkspace else {
            throw CmdFail(windowIsntPartOfTree(window))
        }
        if newState { // Enter fullscreen
            window.bind(to: workspace.macOsNativeFullscreenWindowsContainer, weight: 1)
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
                throw CmdFail(bugPrompt())
            }
        }
    }
}
