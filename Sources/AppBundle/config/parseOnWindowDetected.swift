import Common

struct WindowDetectedCallback: Equatable {
    var matcher: WindowDetectedCallbackMatcher = .command(.empty)
    var checkFurtherCallbacks: Bool = false
    var run: Shell<any Command>

    var debugJson: Json {
        var result: [String: Json] = [:]
        result["matcher"] = switch matcher {
            case .command(let command): .string(command.shellOfCommandsDescription)
            case .legacy(let legacy): legacy.debugJson
        }
        result["commands"] = .string(run.shellOfCommandsDescription)
        return .dict(result)
    }

    static func == (lhs: WindowDetectedCallback, rhs: WindowDetectedCallback) -> Bool {
        lhs.matcher == rhs.matcher && lhs.checkFurtherCallbacks == rhs.checkFurtherCallbacks && lhs.run.strictEquals(rhs.run)
    }
}

/// The parsed TOML table before validation. `run` is mandatory, see ``parseWindowDetectedCallback``
private struct RawWindowDetectedCallback {
    var matcher: WindowDetectedCallbackMatcher = .command(.empty)
    var checkFurtherCallbacks: Bool = false
    var run: Shell<any Command>? = nil
}

struct LegacyWindowDetectedCallbackMatcher: Equatable {
    var appId: String?
    var appNameRegexSubstring: CaseInsensitiveRegex?
    var windowTitleRegexSubstring: CaseInsensitiveRegex?
    var workspace: String?
    var duringAeroSpaceStartup: Bool?

    var debugJson: Json {
        var resultParts: [String] = []
        if let appId {
            resultParts.append("appId=\"\(appId)\"")
        }
        if let appNameRegexSubstring {
            resultParts.append("appNameRegexSubstring=\"\(appNameRegexSubstring.origin)\"")
        }
        if let windowTitleRegexSubstring {
            resultParts.append("windowTitleRegexSubstring=\"\(windowTitleRegexSubstring.origin)\"")
        }
        if let workspace {
            resultParts.append("workspace=\"\(workspace)\"")
        }
        if let duringAeroSpaceStartup {
            resultParts.append("duringAeroSpaceStartup=\(duringAeroSpaceStartup)")
        }
        return .string(resultParts.joined(separator: ", "))
    }
}

enum WindowDetectedCallbackMatcher: Equatable {
    case command(Shell<any Command>)
    case legacy(LegacyWindowDetectedCallbackMatcher)

    static func == (lhs: WindowDetectedCallbackMatcher, rhs: WindowDetectedCallbackMatcher) -> Bool {
        switch (lhs, rhs) {
            case (.command(let command1), .command(let command2)): command1.strictEquals(command2)
            case (.legacy(let matcher1), .legacy(let matcher2)): matcher1 == matcher2
            default: false
        }
    }
}

private let windowDetectedParser: [String: Parser<RawWindowDetectedCallback>] = [
    "if": Parser(\.matcher, parseMatcher),
    "check-further-callbacks": Parser(\.checkFurtherCallbacks, parseBool),
    "run": Parser(\.run, parseShellOfCommandsForConfig),
]

private let matcherParsers: [String: Parser<LegacyWindowDetectedCallbackMatcher>] = [
    "app-id": Parser(\.appId, upcast(parseString)),
    "workspace": Parser(\.workspace, upcast(parseString)),
    "app-name-regex-substring": Parser(\.appNameRegexSubstring, upcast(parseCaseInsensitiveRegex)),
    "window-title-regex-substring": Parser(\.windowTitleRegexSubstring, upcast(parseCaseInsensitiveRegex)),
    "during-aerospace-startup": Parser(\.duringAeroSpaceStartup, upcast(parseBool)),
]

private func upcast<T>(
    _ fun: @escaping @Sendable (OrderedJson, ConfigBacktrace) -> ResOrConfigParseDiagnostic<T>,
) -> @Sendable (OrderedJson, ConfigBacktrace) -> ResOrConfigParseDiagnostic<T?> {
    { fun($0, $1).map(Optional.init) }
}

func parseOnWindowDetectedArray(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> [WindowDetectedCallback] {
    guard let array = parseTomlArray(raw, backtrace).getOrNil(appendErrorTo: &c.errors) else { return [] }
    return array.enumerated().compactMap { (index, raw) in parseWindowDetectedCallback(raw, backtrace + .index(index), &c) }
}

private func parseCaseInsensitiveRegex(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<CaseInsensitiveRegex> {
    parseString(raw, backtrace).flatMap { CaseInsensitiveRegex.new($0).toParsedConfig(backtrace) }
}

private func parseMatcher(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> WindowDetectedCallbackMatcher {
    switch raw {
        case .dict:
            return .legacy(parseTable(raw, LegacyWindowDetectedCallbackMatcher(), matcherParsers, backtrace, &c))
        case .string(let raw):
            return .command(parseCommandForConfig(raw, allowExecAndForget: false, backtrace, &c))
        default:
            // Intentionally skip Table type from the list of expected types
            c.errors.append(.init(backtrace, expectedActualTypeError(expected: .string, actual: raw.tomlType)))
            return .command(.empty)
    }
}

private func parseWindowDetectedCallback(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> WindowDetectedCallback? {
    var myContext = ConfigParserContext(configVersion: c.configVersion, errors: [], warnings: [])
    let callback = parseTable(raw, RawWindowDetectedCallback(), windowDetectedParser, backtrace, &myContext)

    if callback.matcher == .command(.empty) && !callback.checkFurtherCallbacks {
        let msg = "Omitting 'if' is error prone. You can use `if = 'true'` to preserve the previous behavior.\n" +
            "But heads up! You may have missed 'check-further-callbacks = true'"
        myContext.errors.append(.init(backtrace, msg))
    }

    if callback.run == nil {
        myContext.errors.append(.init(backtrace, "'run' is mandatory key"))
    }

    guard let run = callback.run, myContext.errors.isEmpty else {
        c.errors += myContext.errors
        c.warnings += myContext.warnings
        return nil
    }

    return WindowDetectedCallback(matcher: callback.matcher, checkFurtherCallbacks: callback.checkFurtherCallbacks, run: run)
}
