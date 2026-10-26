public struct ExecAndForgetCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public static let parser: CmdParser<Self> = .init(kind: .execAndForget)

    public init(bashScript: String) {
        self.commonState = .init([bashScript])
        self.bashScript = bashScript
    }

    public let bashScript: String
}
