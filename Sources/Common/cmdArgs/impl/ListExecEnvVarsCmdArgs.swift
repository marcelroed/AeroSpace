public struct ListExecEnvVarsCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .listExecEnvVars,
        flags: [:],
        posArgs: [],
    )
}
