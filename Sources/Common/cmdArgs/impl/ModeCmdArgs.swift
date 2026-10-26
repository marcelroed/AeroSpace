public struct ModeCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .mode,
        flags: [:],
        posArgs: [dashDashArg(mandatory: false), newMandatoryPosArgParser(\.targetMode, consumeStrCliArg, placeholder: "<binding-mode>")],
    )

    public var targetMode: Lateinit<String> = .uninitialized
}

func consumeStrCliArg(i: PosArgParserInput) -> ParsedCliArgs<String> { .succ(i.arg, advanceBy: 1) }
