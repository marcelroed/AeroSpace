public struct ListAppsCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .listApps,
        flags: [
            "--macos-native-hidden": boolFlag(\.macosHidden),

            // Formatting flags
            "--format": formatParser(\._format, for: .app),
            "--count": trueBoolFlag(\.outputOnlyCount),
            "--json": trueBoolFlag(\.json),
        ],
        conflictingOptions: [
            ["--count", "--format"],
            ["--count", "--json"],
        ],
    )
    public static let defaultFormat: [InterToken<InterVar>] = [
        .interVar(.formatVar(.app(.appPid))), .interVar(.plainInterVar(.rightPadding)), .literal(" | "),
        .interVar(.formatVar(.app(.appBundleId))), .interVar(.plainInterVar(.rightPadding)), .literal(" | "),
        .interVar(.formatVar(.app(.appName))),
    ]

    public var macosHidden: Bool?
    public var _format: [InterToken<InterVar>] = []
    public var outputOnlyCount: Bool = false
    public var json: Bool = false
}

func parseListAppsCmdArgs(_ args: StrArrSlice) -> ParsedCmd<ListAppsCmdArgs> {
    parseSpecificCmdArgs(ListAppsCmdArgs(rawArgs: args), args)
        .filterFormatCompatibleWithJson()
}
