let subcommandParsers: [String: SubCommandParser] = initSubcommands()

struct SubCommandParser: Sendable {
    let parse: @Sendable (StrArrSlice) -> ParsedCmd<any CmdArgs>

    init<T: CmdArgs>(_ parser: @escaping @Sendable (StrArrSlice) -> ParsedCmd<T>) {
        parse = { args in parser(args).map { $0 } }
    }

    init<T: CmdArgs>(_ raw: @escaping @Sendable (StrArrSlice) -> T) {
        parse = { args in parseSpecificCmdArgs(raw(args), args).map { $0 } }
    }
}
