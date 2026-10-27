import Common

struct WindowDetectedCallback: Equatable {
    var matcher: WindowDetectedCallbackMatcher = .command(.empty)
    var checkFurtherCallbacks: Bool = false
    var run: Shell<any Command>

    var debugJson: OrderedJson {
        var result: OrderedJson.JsonDict = [:]
        result["matcher"] = switch matcher {
            case .command(let command): .string(command.shellOfCommandsDescription)
            case .legacy(let legacy): legacy.debugJson
        }
        result["commands"] = .string(run.shellOfCommandsDescription)
        return .dict(result)
    }

    func matches(_ window: Window) async -> Bool {
        switch self.matcher {
            case .legacy(let matcher):
                if let startupMatcher = matcher.duringAeroSpaceStartup, startupMatcher != isStartup {
                    return false
                }
                if let regex = matcher.windowTitleRegexSubstring, (try? await window.getTitle(.nonCancellable))?.contains(caseInsensitiveRegex: regex) != true {
                    return false
                }
                if let appId = matcher.appId, appId != window.app.rawAppBundleId {
                    return false
                }
                if let regex = matcher.appNameRegexSubstring, !(window.app.name ?? "").contains(caseInsensitiveRegex: regex) {
                    return false
                }
                if let workspace = matcher.workspace, workspace != window.nodeWorkspace?.name {
                    return false
                }
                return true
            case .command(let command):
                return await command.run(.defaultEnv.withWindowId(window.windowId), .emptyStdin).exitCode.rawValue == 0
        }
    }

    static func == (lhs: WindowDetectedCallback, rhs: WindowDetectedCallback) -> Bool {
        lhs.matcher == rhs.matcher && lhs.checkFurtherCallbacks == rhs.checkFurtherCallbacks && lhs.run.strictEquals(rhs.run)
    }
}

struct LegacyWindowDetectedCallbackMatcher: Equatable {
    var appId: String?
    var appNameRegexSubstring: CaseInsensitiveRegex?
    var windowTitleRegexSubstring: CaseInsensitiveRegex?
    var workspace: String?
    var duringAeroSpaceStartup: Bool?

    var debugJson: OrderedJson {
        let parts: [String?] = [
            appId.map { "appId=\"\($0)\"" },
            appNameRegexSubstring.map { "appNameRegexSubstring=\"\($0.origin)\"" },
            windowTitleRegexSubstring.map { "windowTitleRegexSubstring=\"\($0.origin)\"" },
            workspace.map { "workspace=\"\($0)\"" },
            duringAeroSpaceStartup.map { "duringAeroSpaceStartup=\($0)" },
        ]
        return .string(parts.compactMap { $0 }.joined(separator: ", "))
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

func onWindowDetected(_ env: CmdEnv, _ io: CmdIo, _ window: Window) async -> Int32ExitCode {
    broadcastEvent(.windowDetected(
        windowId: window.windowId,
        workspace: window.nodeWorkspace?.name,
        appBundleId: window.app.rawAppBundleId,
        appName: window.app.name,
    ))
    var lastExitCode = Int32ExitCode.succ
    for callback in config.onWindowDetected where await callback.matches(window) {
        lastExitCode = await callback.run.run(env.withWindowId(window.windowId), io)
        if !callback.checkFurtherCallbacks {
            return lastExitCode
        }
    }
    return lastExitCode
}

private let callbackFields: [String: Field<WindowDetectedCallback>] = [
    "if": Field(\.matcher, decodeMatcher),
    "check-further-callbacks": Field(\.checkFurtherCallbacks, decodeBool),
    "run": Field(\.run, decodeShellOfCommands),
]

private let decodeRegex: Decode<CaseInsensitiveRegex> = decodeParsed(CaseInsensitiveRegex.new)

private let legacyMatcherFields: [String: Field<LegacyWindowDetectedCallbackMatcher>] = [
    "app-id": Field(\.appId, decodeString),
    "workspace": Field(\.workspace, decodeString),
    "app-name-regex-substring": Field(\.appNameRegexSubstring, decodeRegex),
    "window-title-regex-substring": Field(\.windowTitleRegexSubstring, decodeRegex),
    "during-aerospace-startup": Field(\.duringAeroSpaceStartup, decodeBool),
]

let decodeWindowRules: Decode<[WindowDetectedCallback]> = { raw, path, d in
    decodeArray(raw, path, &d)?.enumerated().compactMap { index, raw in decodeWindowRule(raw, path + .index(index), &d) }
}

private let decodeMatcher: Decode<WindowDetectedCallbackMatcher> = { raw, path, d in
    switch raw {
        case .dict:
            var matcher = LegacyWindowDetectedCallbackMatcher()
            decodeTable(raw, into: &matcher, legacyMatcherFields, path, &d)
            return .legacy(matcher)
        case .string(let raw):
            return .command(parseCommandForConfig(raw, allowExecAndForget: false, path, &d))
        default:
            // Intentionally skip Table type from the list of expected types
            d.typeMismatch(path, expected: .string, actual: raw)
            return nil
    }
}

/// A rule with any error is dropped
private func decodeWindowRule(_ raw: OrderedJson, _ path: ConfigBacktrace, _ d: inout Diagnostics) -> WindowDetectedCallback? {
    let errorCount = d.errors.count
    var rule = WindowDetectedCallback(run: .empty)
    decodeTable(raw, into: &rule, callbackFields, path, &d)
    if rule.matcher == .command(.empty) && !rule.checkFurtherCallbacks {
        let msg = "Omitting 'if' is error prone. You can use `if = 'true'` to preserve the previous behavior.\n" +
            "But heads up! You may have missed 'check-further-callbacks = true'"
        d.error(path, msg)
    }
    if raw.asDictOrNil?["run"] == nil {
        d.error(path, "'run' is mandatory key")
    }
    return d.errors.count == errorCount ? rule : nil
}
