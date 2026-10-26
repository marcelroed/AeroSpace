public struct SplitCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .split,
        flags: [
            "--window-id": windowIdSubArgParser(),
        ],
        posArgs: [newMandatoryPosArgParser(\.arg, enumPosArg(SplitArg.self), placeholder: SplitArg.unionLiteral)],
    )

    public var arg: Lateinit<SplitArg> = .uninitialized

    public enum SplitArg: String, CaseIterable, Sendable {
        case horizontal, vertical, opposite
    }
}
