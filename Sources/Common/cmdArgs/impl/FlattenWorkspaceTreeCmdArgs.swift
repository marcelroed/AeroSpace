public struct FlattenWorkspaceTreeCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .flattenWorkspaceTree,
        flags: [
            "--workspace": workspaceSubArgParser(),
        ],
    )
}
