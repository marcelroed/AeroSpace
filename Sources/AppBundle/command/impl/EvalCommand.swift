import Common

struct EvalCommand: nonisolated Command {
    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var shellExpr: String

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        while let option = try a.nextOption() {
            switch option {
                case "--stdin": break // For the CLI: it sends its stdin, which the commands of the expression can read
                default: throw .unknownOption(option)
            }
        }
        let result = Self(shellExpr: try a.positional("<aerospace-shell-expr>"))
        try a.end()
        return result
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let shell: Shell<any Command>
        do {
            shell = try parseShell(shellExpr, allowExecAndForget: false, allowEval: false)
        } catch .help {
            throw "--help is not supported inside eval command"
        } catch {
            throw CmdFail(error.message)
        }
        let exitCode = await shell.run(cx.env, cx.io)
        if exitCode != EXIT_CODE_ZERO { throw CmdFail(nil, exitCode: exitCode) }
    }
}
