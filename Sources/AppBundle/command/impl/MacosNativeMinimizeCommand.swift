import AppKit
import Common

/// See: MacosNativeFullscreenCommand. Problem ID-B6E178F2
struct MacosNativeMinimizeCommand: nonisolated Command {
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
        // resolveTargetOrReportError on already minimized windows will always fail
        // It would be easier if minimized windows were part of the workspace in tree hierarchy
        let window = try cx.window(windowId: windowId)
        guard let newState: Bool = try? await !window.isMacosMinimized(.nonCancellable) else { throw CmdFail(bugPrompt()) }
        window.asMacWindow().setNativeMinimized(newState)
        if newState { // minimize
            window.bind(to: macosMinimizedWindowsContainer, weight: 1)
            return
        } else { // unminimize
            throw CmdFail("The command is uncapable of unminimizing windows yet. Sorry") // dead code. should never be possible, see the comment above
        }
    }
}
