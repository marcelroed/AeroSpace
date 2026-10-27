import AppKit
import Common

struct FullscreenCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var toggle: ToggleEnum = .toggle
    var noOuterGaps = false
    var failIfNoop = false
    var windowId: UInt32? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var result = Self()
        while let option = try a.nextOption() {
            switch option {
                case "--no-outer-gaps": result.noOuterGaps = true
                case "--fail-if-noop": result.failIfNoop = true
                case "--window-id": result.windowId = try a.windowId(of: option)
                default: throw .unknownOption(option)
            }
        }
        if let onOff: OnOff = try a.positional() { result.toggle = onOff.toggle }
        try a.end()
        if result.toggle == .off && result.noOuterGaps { throw "--no-outer-gaps is incompatible with 'off' argument" }
        if result.failIfNoop && result.toggle == .toggle { throw "--fail-if-noop requires 'on' or 'off' argument" }
        return result
    }

    func run(_ cx: CmdContext) throws(CmdFail) {
        let window = try cx.window(windowId: windowId)
        let newState = toggle.resolve(current: window.isFullscreen)
        if newState == window.isFullscreen {
            return try noop(cx, failIfNoop: failIfNoop, newState
                ? "Already fullscreen. Tip: use --fail-if-noop to exit with non-zero code"
                : "Already not fullscreen. Tip: use --fail-if-noop to exit with non-zero code")
        }
        window.isFullscreen = newState
        window.noOuterGapsInFullscreen = noOuterGaps

        // Focus on its own workspace
        window.markAsMostRecentChild()
    }
}
