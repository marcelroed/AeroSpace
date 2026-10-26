public struct EnableCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    fileprivate init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .enable,
        flags: [
            "--fail-if-noop": trueBoolFlag(\.failIfNoop),
        ],
        posArgs: [newMandatoryPosArgParser(\.targetState, enumPosArg(State.self), placeholder: EnableCmdArgs.State.unionLiteral)],
    )
    public var targetState: Lateinit<State> = .uninitialized
    public var failIfNoop: Bool = false

    public init(rawArgs: [String], targetState: State) {
        self.commonState = .init(rawArgs.slice)
        self.targetState = .initialized(targetState)
    }

    public enum State: String, CaseIterable, Sendable {
        case on, off, toggle
    }
}

func parseEnableCmdArgs(_ args: StrArrSlice) -> ParsedCmd<EnableCmdArgs> {
    return parseSpecificCmdArgs(EnableCmdArgs(rawArgs: args), args)
        .filterNot("--fail-if-noop is incompatible with 'toggle' argument") { $0.targetState.val == .toggle && $0.failIfNoop }
}
