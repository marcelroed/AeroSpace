public struct ListMonitorsCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .listMonitors,
        flags: [
            "--focused": boolFlag(\.focused),
            "--mouse": boolFlag(\.mouse),

            // Formatting flags
            "--format": formatParser(\._format, for: .monitor),
            "--count": trueBoolFlag(\.outputOnlyCount),
            "--json": trueBoolFlag(\.json),
        ],
        conflictingOptions: [
            ["--count", "--format"],
            ["--count", "--json"],
        ],
    )
    public static let defaultFormat: [InterToken<InterVar>] = [
        .interVar(.formatVar(.monitor(.monitorId_oneBased))), .interVar(.plainInterVar(.rightPadding)), .literal(" | "),
        .interVar(.formatVar(.monitor(.monitorName))),
    ]

    public var focused: Bool?
    public var mouse: Bool?
    public var _format: [InterToken<InterVar>] = []
    public var outputOnlyCount: Bool = false
    public var json: Bool = false
}

func parseListMonitorsCmdArgs(_ args: StrArrSlice) -> ParsedCmd<ListMonitorsCmdArgs> {
    parseSpecificCmdArgs(ListMonitorsCmdArgs(rawArgs: args), args)
        .filterFormatCompatibleWithJson()
}
