import AppKit
import Common

struct CloseCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var quitIfLastWindow = false
    var windowId: UInt32? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var result = Self()
        while let option = try a.nextOption() {
            switch option {
                case "--quit-if-last-window": result.quitIfLastWindow = true
                case "--window-id": result.windowId = try a.windowId(of: option)
                default: throw .unknownOption(option)
            }
        }
        try a.end()
        return result
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let window = try cx.window(windowId: windowId, noWindowMsg: "Empty workspace")
        // Access ax directly. Not cool :(
        if await quitIfLastWindow.andAsync({ @MainActor @Sendable in (try? await window.asMacWindow().macApp.getAxWindowsCount(.nonCancellable)) == 1 }) {
            let app = window.asMacWindow().macApp
            guard app.nsApp.terminate() else { throw "Failed to quit '\(window.app.name ?? "Unknown app")'" }
            for workspace in Workspace.all {
                for window in workspace.allLeafWindowsRecursive where window.app.pid == app.pid {
                    window.asMacWindow().garbageCollect(skipClosedWindowsCache: true)
                }
            }
        } else {
            window.closeAxWindow()
        }
    }
}

struct CloseAllWindowsButCurrentCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var quitIfLastWindow = false

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var result = Self()
        while let option = try a.nextOption() {
            switch option {
                case "--quit-if-last-window": result.quitIfLastWindow = true
                default: throw .unknownOption(option)
            }
        }
        try a.end()
        return result
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let target = try cx.target()
        guard let focused = target.windowOrNil else { throw "Empty workspace" }
        var failed = false
        for window in target.workspace.allLeafWindowsRecursive where window != focused {
            let close = CloseCommand(quitIfLastWindow: quitIfLastWindow)
            failed = await close.run(cx.env.withWindowId(window.windowId), cx.io) != EXIT_CODE_ZERO || failed
        }
        if failed { throw .silent }
    }
}
