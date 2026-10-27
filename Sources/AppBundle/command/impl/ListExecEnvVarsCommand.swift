import AppKit
import Common

struct ListExecEnvVarsCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        try a.noArgs()
        return Self()
    }

    func run(_ cx: CmdContext) {
        for (key, value) in config.execConfig.envVariables.sorted(by: { $0.key < $1.key }) {
            cx.out("\(key)=\(value)")
        }
    }
}
