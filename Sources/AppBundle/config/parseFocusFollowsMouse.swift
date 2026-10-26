private let focusFollowsMouseParserTable: [String: Parser<FocusFollowsMouse>] = [
    "enabled": Parser(\.enabled, parseBool),
]

func parseFocusFollowsMouse(_ rawConfig: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> FocusFollowsMouse {
    parseTable(rawConfig, FocusFollowsMouse(), focusFollowsMouseParserTable, backtrace, &c)
}
