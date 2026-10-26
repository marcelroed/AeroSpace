public struct TestNotCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .testNot,
        flags: [:],
        posArgs: [],
    )
    public typealias ExitCodeType = ConditionalExitCode

    public var testArgs = TestCmdArgs(rawArgs: [])
}

func parseTestNotCmdArgs(_ args: StrArrSlice) -> ParsedCmd<TestNotCmdArgs> {
    parseSpecificCmdArgs(TestCmdArgs(rawArgs: args), args).map {
        TestNotCmdArgs(rawArgs: args).copy(\.testArgs, $0)
    }
}
