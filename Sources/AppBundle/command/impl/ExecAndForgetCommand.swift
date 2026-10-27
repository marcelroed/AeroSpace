import AppKit
import Common

/// Only the config knows it: the rest of the line after the name is a bash script (parseShell)
struct ExecAndForgetCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    let bashScript: String

    /// The script isn't a word: it's the rest of the line, unquoted
    var description: String { "exec-and-forget" + bashScript }

    func run(_ cx: CmdContext) throws(CmdFail) {
        // todo shall exec-and-forget fork exec session?
        // It doesn't throw if exit code is non-zero
        let process = Process()
        process.environment = config.execConfig.envVariables + cx.env.asMap
        process.executableURL = URL(filePath: "/bin/bash")
        process.arguments = ["-c", bashScript]
        if (try? process.run()) == nil { throw .silent }
    }
}
