import AppKit
import Common

struct ConfigCommand: nonisolated Command {
    nonisolated enum Mode: Equatable, Sendable {
        /// `--keys` lists the sorted keys of a table
        case getKey(key: String, json: Bool = false, keys: Bool = false)
        case majorKeys, allKeys, configPath
    }

    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var mode: Mode

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var keyNameToGet: String? = nil
        var majorKeys = false
        var allKeys = false
        var configPath = false
        var json = false
        var keys = false
        while let option = try a.nextOption() {
            switch option {
                case "--json": json = true
                case "--keys": keys = true
                case "--major-keys": majorKeys = true
                case "--all-keys": allKeys = true
                case "--config-path": configPath = true
                case "--get": keyNameToGet = try a.value(of: option, "<name>")
                default: throw .unknownOption(option)
            }
        }
        try a.end()
        let modes: [(String, Mode)] = [
            keyNameToGet.map { ("--get", .getKey(key: $0, json: json, keys: keys)) },
            majorKeys ? ("--major-keys", .majorKeys) : nil,
            allKeys ? ("--all-keys", .allKeys) : nil,
            configPath ? ("--config-path", .configPath) : nil,
        ].compactMap(\.self)
        guard let (_, mode) = modes.singleOrNil() else {
            if modes.isEmpty { throw "Mandatory flag is not specified (--get|--major-keys|--all-keys|--config-path)" }
            throw "Conflicting flags are specified: \(modes.map(\.0).joined(separator: ", "))"
        }
        if keys && keyNameToGet == nil { throw "--keys flag requires --get flag" }
        if json && keyNameToGet == nil { throw "--json flag requires --get flag" }
        return Self(mode: mode)
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        switch mode {
            case .getKey(let key, let json, let keys):
                try getKey(cx, key: key, json: json, keys: keys)
            case .majorKeys:
                let out = """
                    .
                    mode
                    \(config.modes.keys.sorted().map { "mode.\($0).binding" }.joined(separator: "\n"))
                    """
                cx.out(out)
            case .allKeys:
                let configMap = buildConfigMap()
                var allKeys: [String] = []
                configMap.dumpAllKeysRecursive(path: ".", result: &allKeys)
                cx.out(allKeys.joined(separator: "\n"))
            case .configPath:
                cx.out(world.configUrl.absoluteURL.path)
        }
    }

    private func getKey(_ cx: CmdContext, key: String, json: Bool, keys: Bool) throws(CmdFail) {
        let configMap = try buildConfigMap().find(keyPath: try key.toKeyPath()[...])
        switch configMap {
            case .string(let string) where keys:
                throw "--keys flag cannot be applied to scalar object '\(string)'"
            case .table(let table) where keys:
                let keys = table.keys.sorted()
                if json {
                    try printJson(cx, .array(keys.map(OrderedJson.string)))
                } else {
                    cx.out(keys.joined(separator: "\n"))
                }
            case _ where json:
                try printJson(cx, configMap.json)
            case .table:
                throw "Complicated objects can be printed only with --json flag. Alternatively, you can try to inspect keys of the object with --keys flag"
            case .string(let string):
                cx.out(string)
        }
    }

    private func printJson(_ cx: CmdContext, _ json: OrderedJson) throws(CmdFail) {
        guard let json = JSONEncoder.aeroSpaceDefault.encodeToString(json) else { throw "Can't convert json Data to String" }
        cx.out(json)
    }
}

extension String {
    fileprivate func toKeyPath() throws(CmdFail) -> [String] {
        if self == "." { return [] }
        if isEmpty { throw "Invalid empty key" }
        if contains("..") || hasSuffix(".") { throw "Invalid key '\(self)'" }
        return split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    }
}

extension Shell<any Command> {
    var shellOfCommandsDescription: String { buildDescription { $0.description } }
}

struct ReloadConfigCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var noGui = false
    var dryRun = false

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var result = Self()
        while let option = try a.nextOption() {
            switch option {
                case "--no-gui": result.noGui = true
                case "--dry-run": result.dryRun = true
                case "--warnings-as-errors": break // No effect: config warnings no longer exist. Scripts still pass it
                default: throw .unknownOption(option)
            }
        }
        try a.end()
        return result
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let result = await reloadConfig_nonCancellable(args: self)
        if !result.stdout.isEmpty {
            cx.out(result.stdout)
        }
        if !result.isOk { throw .silent }
    }
}

struct ReloadConfigResult {
    let isOk: Bool
    let stdout: String
}

/// Stays `async` only so that the call sites don't change. Nothing in it suspends
func reloadConfig_nonCancellable(
    args: ReloadConfigCommand = ReloadConfigCommand(),
    forceConfigUrl: URL? = nil,
) async -> ReloadConfigResult {
    let (url, parsed) = loadConfig(forceUrl: forceConfigUrl)
    let errors = parsed.errors.map(\.description)
    if !args.noGui {
        MessageModel.shared.message = errors.isEmpty
            ? nil
            : Message(body: "Failed to parse \(url.absoluteURL.path.singleQuoted). \(errors.count) error(s)\n\n\(errors.joined(separator: "\n\n"))")
    }
    if case .parsed(let newConfig, _) = parsed, !args.dryRun {
        applyConfig(newConfig, url: url)
    }
    if !args.dryRun {
        // Re-arm even if the reload failed. The watcher follows the file, not the path, and an atomic save replaces the file
        syncConfigFileWatcher()
    }
    return ReloadConfigResult(isOk: errors.isEmpty, stdout: errors.joined(separator: "\n\n"))
}

/// Synchronous on purpose: no hotkey press, CLI request or window rule can observe a half-applied config
private func applyConfig(_ newConfig: Config, url: URL) {
    resetHotKeys()
    world.config = newConfig
    world.configUrl = url
    registerHotkeys(for: world.activeMode) // A removed mode keeps its stale name and gets no hotkeys
    syncStartAtLogin()
    syncFocusFollowsMouse(config)
}

/// Finds and parses the config
func loadConfig(forceUrl: URL?) -> (url: URL, result: ParseConfigResult) {
    let url: URL
    if let forceUrl {
        url = forceUrl
    } else {
        switch findCustomConfigUrl() {
            case .file(let found): url = found
            case .noCustomConfigExists: url = defaultConfigUrl
            case .ambiguousConfigError(let candidates):
                return (defaultConfigUrl, .fatal("Ambiguous config error. Several configs found:\n" + candidates.map(\.path).joined(separator: "\n")))
        }
    }
    do {
        return (url, parseConfig(try String(contentsOf: url, encoding: .utf8)))
    } catch {
        return (url, .fatal("Can't read contents of \(url.path.singleQuoted) as a utf8 string: \(error.localizedDescription)"))
    }
}
