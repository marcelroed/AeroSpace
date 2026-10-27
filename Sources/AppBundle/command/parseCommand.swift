import Common

func parseCommand(
    _ raw: String,
    allowExecAndForget: Bool,
    allowEval: Bool,
) -> ParsedCmd<Shell<any Command>> {
    if allowExecAndForget && raw.starts(with: "exec-and-forget") {
        let bashScript = raw.removePrefix("exec-and-forget")
        if bashScript.first?.isWhitespace ?? true { // Don't take `exec-and-forgetfoo` for `exec-and-forget foo`
            return .cmd(.cmd(ExecAndForgetCommand(args: ExecAndForgetCmdArgs(bashScript: bashScript))))
        }
    }
    return switch raw.lexAndParseShell() {
        case .success(let it):
            it.flatMap { args in
                parseCommand(args).flatMap { cmd in
                    cmd is EvalCommand && !allowEval ? .failure("Illegal eval (Tip: nested evals are forbidden)", EXIT_CODE_TWO) : .cmd(cmd)
                }
            }
        case .failure(let it): ParsedCmd.failure(it, EXIT_CODE_TWO)
    }
}

func parseCommand(_ args: [String]) -> ParsedCmd<any Command> {
    parseCmdArgs(args.slice).flatMap { $0.toCommand() }
}
