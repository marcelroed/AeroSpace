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
        result["check-further-callbacks"] = .bool(checkFurtherCallbacks)
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
                return await command.run(.defaultEnv.withWindowId(window.windowId), .emptyStdin).exitCode == EXIT_CODE_ZERO
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

    /// Keyed like the config, so that JSON escapes the values
    var debugJson: OrderedJson {
        var result: OrderedJson.JsonDict = [:]
        result["app-id"] = appId.map(OrderedJson.string)
        result["app-name-regex-substring"] = appNameRegexSubstring.map { .string($0.origin) }
        result["window-title-regex-substring"] = windowTitleRegexSubstring.map { .string($0.origin) }
        result["workspace"] = workspace.map(OrderedJson.string)
        result["during-aerospace-startup"] = duringAeroSpaceStartup.map(OrderedJson.bool)
        return .dict(result)
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

func onWindowDetected(_ env: CmdEnv, _ io: CmdIo, _ window: Window) async -> Int32 {
    broadcastEvent(.windowDetected(
        windowId: window.windowId.raw,
        workspace: window.nodeWorkspace?.name,
        appBundleId: window.app.rawAppBundleId,
        appName: window.app.name,
    ))
    var lastExitCode = EXIT_CODE_ZERO
    for callback in config.onWindowDetected where await callback.matches(window) {
        if !window.isAlive { break } // The window closed at a suspension point
        lastExitCode = await callback.run.run(env.withWindowId(window.windowId), io)
        if !callback.checkFurtherCallbacks {
            return lastExitCode
        }
    }
    return lastExitCode
}

private let callbackFields: [String: Field<WindowDetectedCallback>] = [
    "if": .ignored, // Decoded in decodeWindowRule: an omitted 'if' and an unusable one differ
    "check-further-callbacks": Field(\.checkFurtherCallbacks, decodeBool),
    "run": Field(\.run, decodeShellOfCommands),
]

private let decodeRegex: Decode<CaseInsensitiveRegex> = decodeParsed(CaseInsensitiveRegex.init)

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
            return decodeTable(raw, into: &matcher, legacyMatcherFields, path, &d) ? .legacy(matcher) : nil
        case .string(let raw):
            return parseCommandForConfig(raw, allowExecAndForget: false, path, &d).map(WindowDetectedCallbackMatcher.command)
        default:
            // Intentionally skip Table type from the list of expected types
            d.typeMismatch(path, expected: .string, actual: raw)
            return nil
    }
}

/// A rule with any error is dropped
private func decodeWindowRule(_ raw: OrderedJson, _ path: ConfigBacktrace, _ d: inout Diagnostics) -> WindowDetectedCallback? {
    guard let table = decodeDict(raw, path, &d) else { return nil }
    var rule = WindowDetectedCallback(run: .empty)
    var isUsable = decodeTable(raw, into: &rule, callbackFields, path, &d)
    // An omitted 'if' is the empty command. `nil`: the 'if' is unusable, and its error is reported
    let matcher = table["if"].map { decodeMatcher($0, path + .key("if"), &d) } ?? .command(.empty)
    if let matcher {
        rule.matcher = matcher
    } else {
        isUsable = false
    }
    if matcher == .command(.empty) && !rule.checkFurtherCallbacks {
        let msg = "Omitting 'if' is error prone. You can use `if = 'true'` to preserve the previous behavior.\n" +
            "But heads up! You may have missed 'check-further-callbacks = true'"
        d.error(path, msg)
        isUsable = false
    }
    if table["run"] == nil {
        d.error(path, "'run' is mandatory key")
        isUsable = false
    }
    return isUsable ? rule : nil
}
