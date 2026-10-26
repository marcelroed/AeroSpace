public struct JoinWithCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .joinWith,
        flags: [
            "--window-id": windowIdSubArgParser(),
        ],
        posArgs: [newMandatoryPosArgParser(\.direction, enumPosArg(CardinalDirection.self), placeholder: CardinalDirection.unionLiteral)],
    )

    public var direction: Lateinit<CardinalDirection> = .uninitialized
}
