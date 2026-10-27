import Common

/// Parses a command line of the config or of `eval`: an aerospace shell expression
func parseShell(_ raw: String, allowExecAndForget: Bool, allowEval: Bool) throws(CmdParseError) -> Shell<any Command> {
    if allowExecAndForget && raw.starts(with: "exec-and-forget") {
        let bashScript = raw.removePrefix("exec-and-forget")
        if bashScript.first?.isWhitespace ?? true { // Don't take `exec-and-forgetfoo` for `exec-and-forget foo`
            return .cmd(ExecAndForgetCommand(bashScript: bashScript))
        }
    }
    return try raw.lexAndParseShell().map { (words) throws(CmdParseError) in
        let command = try parseCommand(words)
        if command is EvalCommand && !allowEval { throw "Illegal eval (Tip: nested evals are forbidden)" }
        return command
    }
}

/// What the args of a CLI request ask for
enum ParsedRequest {
    case command(any Command)
    /// Not a command: it holds the connection open
    case subscribe(SubscribeArgs)
}

/// Parses the args of a CLI request. They are untrusted: no input may trap, since the server would crash
func parseRequest(_ args: [String]) throws(CmdParseError) -> ParsedRequest {
    var (kind, cursor) = try parseSubcommand(args)
    if kind == .subscribe { return .subscribe(try SubscribeArgs.parse(&cursor)) }
    return .command(try parseCommand(args))
}

/// Parses the words of one command: the subcommand and its args
func parseCommand(_ words: [String]) throws(CmdParseError) -> any Command {
    let (kind, cursor) = try parseSubcommand(words)
    var args = cursor
    var command = try parseArgs(kind, &args)
    command.source = SourceWords(words)
    return command
}

/// The subcommand of `words` and a cursor over its args
func parseSubcommand(_ words: [String]) throws(CmdParseError) -> (CmdKind, ArgCursor) {
    guard let name = words.first, !name.isEmpty else { throw "Can't parse empty string command" }
    guard let kind = CmdKind(rawValue: name), kind != .execAndForget else { throw "Unrecognized subcommand '\(name)'" }
    let args = Array(words.dropFirst())
    if args.prefix(while: { $0 != "--" }).contains(where: { $0 == "-h" || $0 == "--help" }) { throw .help(kind) }
    return (kind, ArgCursor(args))
}

/// One case per subcommand, so that every help entry has a command
private func parseArgs(_ kind: CmdKind, _ a: inout ArgCursor) throws(CmdParseError) -> any Command {
    switch kind {
        case .balanceSizes: try BalanceSizesCommand.parse(&a)
        case .close: try CloseCommand.parse(&a)
        case .closeAllWindowsButCurrent: try CloseAllWindowsButCurrentCommand.parse(&a)
        case .config: try ConfigCommand.parse(&a)
        case .debugWindows: try DebugWindowsCommand.parse(&a)
        case .echo: try EchoCommand.parse(&a)
        case .enable: try EnableCommand.parse(&a)
        case .eval: try EvalCommand.parse(&a)
        case .execAndForget: throw "exec-and-forget is not a real command and it's NOT allowed in the shell"
        case ._false: try FalseCommand.parse(&a)
        case .flattenWorkspaceTree: try FlattenWorkspaceTreeCommand.parse(&a)
        case .focus: try FocusCommand.parse(&a)
        case .focusBackAndForth: try FocusBackAndForthCommand.parse(&a)
        case .focusMonitor: try FocusMonitorCommand.parse(&a)
        case .fullscreen: try FullscreenCommand.parse(&a)
        case .joinWith: try JoinWithCommand.parse(&a)
        case .layout: try LayoutCommand.parse(&a)
        case .listApps: try ListAppsCommand.parse(&a)
        case .listExecEnvVars: try ListExecEnvVarsCommand.parse(&a)
        case .listModes: try ListModesCommand.parse(&a)
        case .listMonitors: try ListMonitorsCommand.parse(&a)
        case .listWindows: try ListWindowsCommand.parse(&a)
        case .listWorkspaces: try ListWorkspacesCommand.parse(&a)
        case .macosNativeFullscreen: try MacosNativeFullscreenCommand.parse(&a)
        case .macosNativeMinimize: try MacosNativeMinimizeCommand.parse(&a)
        case .mode: try ModeCommand.parse(&a)
        case .move: try MoveCommand.parse(&a)
        case .moveMouse: try MoveMouseCommand.parse(&a)
        case .moveNodeToMonitor: try MoveNodeToMonitorCommand.parse(&a)
        case .moveNodeToWorkspace: try MoveNodeToWorkspaceCommand.parse(&a)
        case .moveWorkspaceToMonitor: try MoveWorkspaceToMonitorCommand.parse(&a)
        case .reloadConfig: try ReloadConfigCommand.parse(&a)
        case .resize: try ResizeCommand.parse(&a)
        case .runCallback: try RunCallbackCommand.parse(&a)
        case .split: try SplitCommand.parse(&a)
        case .subscribe: throw "subscribe is only available from the CLI"
        case .summonWorkspace: try SummonWorkspaceCommand.parse(&a)
        case .swap: try SwapCommand.parse(&a)
        case .test: try TestCommand.parse(&a, negated: false)
        case .testNot: try TestCommand.parse(&a, negated: true)
        case .triggerBinding: try TriggerBindingCommand.parse(&a)
        case ._true: try TrueCommand.parse(&a)
        case .volume: try VolumeCommand.parse(&a)
        case .workspace: try WorkspaceCommand.parse(&a)
        case .workspaceBackAndForth: try WorkspaceBackAndForthCommand.parse(&a)
    }
}

/// The args of a command, after the subcommand name. A command's `parse` takes the options in a loop
/// (`nextOption`, and `value(of:)` for their values), and then the positional args, which the loop sets aside.
/// Options come before `--`, start with `-`, and aren't `-` or negative numbers
nonisolated struct ArgCursor {
    private var rest: ArraySlice<String>
    private var positionals: ArraySlice<String> = []
    private var seenOptions: Set<String> = []
    private var afterDoubleDash = false
    /// The index in `positionals` of the first one after `--`
    private var literalPositionalsStart: Int? = nil

    init(_ args: [String]) { rest = args[...] }

    /// The next option. Fails on a repeated option
    mutating func nextOption() throws(CmdParseError) -> String? {
        while let word = rest.popFirst() {
            if word == "--" && !afterDoubleDash {
                afterDoubleDash = true
                literalPositionalsStart = positionals.endIndex
            } else if afterDoubleDash || !isOption(word) {
                positionals.append(word)
            } else if !seenOptions.insert(word).inserted {
                throw "Duplicated option '\(word)'"
            } else {
                return word
            }
        }
        return nil
    }

    /// Fails if more than one option of a set was given
    func checkConflicts(_ sets: [String]...) throws(CmdParseError) {
        for set in sets {
            let given = set.filter(seenOptions.contains)
            if given.count > 1 { throw .conflicting(given) }
        }
    }

    /// For a command without options
    mutating func noOptions() throws(CmdParseError) {
        if let option = try nextOption() { throw .unknownOption(option) }
    }

    /// For a command without args
    mutating func noArgs() throws(CmdParseError) {
        try noOptions()
        try end()
    }

    /// The value of the option just taken: the next word, unless it's an option or `--`
    mutating func valueOrNil() -> String? {
        guard let word = rest.first, word != "--", !isOption(word) else { return nil }
        rest.removeFirst()
        return word
    }

    mutating func value(of option: String, _ placeholder: String) throws(CmdParseError) -> String {
        guard let value = valueOrNil() else { throw "'\(option)' must be followed by '\(placeholder)'" }
        return value
    }

    mutating func value<T>(of option: String, _ placeholder: String, _ parse: (String) throws(CmdParseError) -> T) throws(CmdParseError) -> T {
        let raw = try value(of: option, placeholder)
        do {
            return try parse(raw)
        } catch {
            throw "Failed to parse '\(raw)' CLI argument: \(error.message)"
        }
    }

    mutating func value<T: RawRepresentable & CaseIterable>(of option: String, _ placeholder: String) throws(CmdParseError) -> T where T.RawValue == String {
        try parseEnum(value(of: option, placeholder))
    }

    /// The value of a flag that takes an optional `no`: `--empty` is true, `--empty no` is false
    mutating func noOrTrue() -> Bool {
        if rest.first == "no" {
            rest.removeFirst()
            return false
        }
        return true
    }

    /// The values of the option just taken: the words up to the next option or `--`
    mutating func values() -> [String] {
        let values = rest.prefix { $0 != "--" && !isOption($0) }
        rest.removeFirst(values.count)
        return Array(values)
    }

    mutating func windowId(of option: String) throws(CmdParseError) -> UInt32 {
        try value(of: option, "<window-id>", parseUInt32)
    }

    mutating func workspace(of option: String) throws(CmdParseError) -> WorkspaceName {
        try value(of: option, "<workspace>", WorkspaceName.parse)
    }

    /// The next positional arg. Call after the options
    mutating func positional() -> String? {
        check(rest.isEmpty, "Take the options first")
        return positionals.popFirst()
    }

    /// The next positional arg, and whether it came after `--`: there, `next` is a workspace name rather than a keyword
    mutating func positionalAndIsLiteral(_ placeholder: String) throws(CmdParseError) -> (String, isLiteral: Bool) {
        let index = positionals.startIndex
        let arg = try positional(placeholder)
        return (arg, literalPositionalsStart.map { index >= $0 } ?? false)
    }

    mutating func positional(_ placeholder: String) throws(CmdParseError) -> String {
        guard let arg = positional() else { throw "Argument '\(placeholder)' is mandatory" }
        return arg
    }

    mutating func positional<T: RawRepresentable & CaseIterable>() throws(CmdParseError) -> T? where T.RawValue == String {
        try positional().map { (raw) throws(CmdParseError) in try parseEnum(raw) }
    }

    mutating func positional<T: RawRepresentable & CaseIterable>(_: T.Type = T.self) throws(CmdParseError) -> T where T.RawValue == String {
        try parseEnum(positional(T.unionLiteral))
    }

    /// The remaining positional args. Call after the options
    mutating func allPositionals() -> [String] {
        check(rest.isEmpty, "Take the options first")
        defer { positionals = [] }
        return Array(positionals)
    }

    /// Fails on a positional arg that nothing took
    func end() throws(CmdParseError) {
        if let arg = positionals.first { throw "Unknown argument '\(arg)'" }
    }
}

extension CmdParseError {
    static func unknownOption(_ option: String) -> Self { "Unknown flag '\(option)'" }
    static func conflicting(_ options: String...) -> Self { conflicting(options) }
    static func conflicting(_ options: [String]) -> Self { "Conflicting options: \(options.sorted().joined(separator: ", "))" }
}

nonisolated private func isOption(_ word: String) -> Bool {
    var chars = word.makeIterator()
    return chars.next() == "-" && chars.next().map { !$0.isNumber } == true
}

nonisolated func parseEnum<T: RawRepresentable & CaseIterable>(_ raw: String, _: T.Type = T.self) throws(CmdParseError) -> T where T.RawValue == String {
    guard let value = T(rawValue: raw) else { throw "Can't parse '\(raw)'.\nPossible values: \(T.unionLiteral)" }
    return value
}

nonisolated func parseUInt32(_ raw: String) throws(CmdParseError) -> UInt32 {
    guard let value = UInt32(raw) else { throw "Can't convert '\(raw)' to UInt32" }
    return value
}

nonisolated func parseInt32(_ raw: String) throws(CmdParseError) -> Int32 {
    guard let value = Int32(raw) else { throw "Can't convert '\(raw)' to Int32" }
    return value
}
