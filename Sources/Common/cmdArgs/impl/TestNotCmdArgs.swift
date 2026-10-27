public struct TestNotCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(kind: .testNot)
    public typealias ExitCodeType = ConditionalExitCode

    public var testArgs = TestCmdArgs(rawArgs: [])
}

func parseTestNotCmdArgs(_ args: StrArrSlice) -> ParsedCmd<TestNotCmdArgs> {
    switch parseSpecificCmdArgs(TestCmdArgs(rawArgs: args), args) {
        case .help: .help(TestNotCmdArgs.parser.kind.help)
        case let parsed: parsed.map { TestNotCmdArgs(rawArgs: args).copy(\.testArgs, $0) }
    }
}
