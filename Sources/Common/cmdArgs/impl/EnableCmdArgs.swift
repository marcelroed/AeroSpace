public struct EnableCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    fileprivate init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .enable,
        flags: [
            "--fail-if-noop": trueBoolFlag(\.failIfNoop),
        ],
        posArgs: [newMandatoryPosArgParser(\.targetState, enumPosArg(ToggleEnum.self), placeholder: ToggleEnum.unionLiteral)],
    )
    public var targetState: Lateinit<ToggleEnum> = .uninitialized
    public var failIfNoop: Bool = false

    public init(rawArgs: [String], targetState: ToggleEnum) {
        self.commonState = .init(rawArgs.slice)
        self.targetState = .initialized(targetState)
    }
}

func parseEnableCmdArgs(_ args: StrArrSlice) -> ParsedCmd<EnableCmdArgs> {
    return parseSpecificCmdArgs(EnableCmdArgs(rawArgs: args), args)
        .filterNot("--fail-if-noop is incompatible with 'toggle' argument") { $0.targetState.val == .toggle && $0.failIfNoop }
}
