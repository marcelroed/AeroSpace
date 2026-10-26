public struct CloseAllWindowsButCurrentCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .closeAllWindowsButCurrent,
        flags: [
            "--quit-if-last-window": ArgParser(\.closeArgs.quitIfLastWindow, constSubArgParserFun(true)),
        ],
    )

    public var closeArgs = CloseCmdArgs(rawArgs: [])
}
