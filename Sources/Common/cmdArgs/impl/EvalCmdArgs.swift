public struct EvalCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .eval,
        flags: [
            "--stdin": ArgParser(\.commonState.explicitStdinFlag, constSubArgParserFun(true)),
        ],
        posArgs: [
            dashDashArg(mandatory: false),
            newMandatoryPosArgParser(\.shellExpr, consumeStrCliArg, placeholder: "<aerospace-shell-expr>"),
        ],
        conflictingOptions: [],
    )

    public var shellExpr: Lateinit<String> = .uninitialized
    /*conforms*/ public typealias ExitCodeType = Int32ExitCode
}
