import AppKit
import Common

struct ModeCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var targetMode: String

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        try a.noOptions()
        let result = Self(targetMode: try a.positional("<binding-mode>"))
        try a.end()
        return result
    }

    func run(_ cx: CmdContext) async {
        await activateMode_nonCancellable(targetMode)
    }
}
