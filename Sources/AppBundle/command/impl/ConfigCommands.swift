import AppKit
import Common

struct ConfigCommand: nonisolated Command {
    nonisolated enum Mode: Equatable, Sendable {
        case getKey(key: String), majorKeys, allKeys, configPath
    }

    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var mode: Mode
    var json = false
    var keys = false

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
            keyNameToGet.map { ("--get", .getKey(key: $0)) },
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
        return Self(mode: mode, json: json, keys: keys)
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        switch mode {
            case .getKey(let key):
                try getKey(cx, key: key)
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
                cx.out(configUrl.absoluteURL.path)
        }
    }

    /// `buildConfigMap()` contains only dicts and strings, and `--keys` turns a dict into an array of strings
    private func getKey(_ cx: CmdContext, key: String) throws(CmdFail) {
        let keyPath: [String]
        switch key.toKeyPath() {
            case .success(let it): keyPath = it
            case .failure(let msg): throw CmdFail(msg)
        }
        var configMap: OrderedJson
        switch buildConfigMap().find(keyPath: keyPath.slice) {
            case .success(let it): configMap = it
            case .failure(let msg): throw CmdFail(msg)
        }
        if keys {
            guard let dict = configMap.asDictOrNil else {
                throw "--keys flag cannot be applied to scalar object '\(configMap.scalarDescription.orDie())'"
            }
            configMap = .array(dict.keys.sorted().map { .string($0) })
        }
        if json {
            guard let json = JSONEncoder.aeroSpaceDefault.encodeToString(configMap) else { throw "Can't convert json Data to String" }
            cx.out(json)
            return
        }
        switch configMap {
            case .dict:
                throw "Complicated objects can be printed only with --json flag. Alternatively, you can try to inspect keys of the object with --keys flag"
            case .array(let keys): cx.out(keys.compactMap(\.asStringOrNil).sorted().joined(separator: "\n"))
            case .string, .int, .bool, .null: cx.out(configMap.scalarDescription.orDie())
        }
    }
}

extension String {
    fileprivate func toKeyPath() -> Result<[String], String> {
        if self == "." { return .success([]) }
        if isEmpty { return .failure("Invalid empty key") }
        if contains("..") || hasSuffix(".") { return .failure("Invalid key '\(self)'") }
        return .success(split(separator: ".", omittingEmptySubsequences: false).map(String.init))
    }
}

extension OrderedJson {
    /// The plain text of a scalar, nil for a dict or an array
    fileprivate var scalarDescription: String? {
        switch self {
            case .string(let string): string
            case .int(let int): String(int)
            case .bool(let bool): String(bool)
            case .null: "null"
            case .dict, .array: nil
        }
    }

    func find(keyPath: StrArrSlice) -> Result<OrderedJson, String> {
        guard let key = keyPath.first else { return .success(self) }
        let child: OrderedJson
        switch self {
            case .string, .int, .bool, .null:
                return .failure("Can't dereference scalar value '\(scalarDescription.orDie())'")
            case .dict(let dict):
                guard let value = dict[key] else { return .failure("No value at key token '\(key)'") }
                child = value
            case .array(let array):
                guard let index = Int(key) else { return .failure("Can't convert key token '\(key)' to Int") }
                guard let value = array.getOrNil(atIndex: index) else {
                    return .failure("Index out of bounds. Index: \(index), Size: \(array.count)")
                }
                child = value
        }
        return child.find(keyPath: keyPath.slice(1...).orDie())
    }

    func dumpAllKeysRecursive(path: String, result: inout [String]) {
        result.append(path)
        switch self {
            case .string, .int, .bool, .null: break
            case .dict(let dict):
                for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
                    let path = path == "." ? key : path + "." + key
                    value.dumpAllKeysRecursive(path: path, result: &result)
                }
            case .array(let array):
                for (index, value) in array.enumerated() {
                    let path = path == "." ? String(index) : path + "." + String(index)
                    value.dumpAllKeysRecursive(path: path, result: &result)
                }
        }
    }
}

extension Shell<any Command> {
    var shellOfCommandsDescription: String { buildDescription { $0.description } }
}

func buildConfigMap() -> OrderedJson {
    let modes = config.modes.mapValues { mode in
        var bindings: OrderedJson.JsonDict = [:]
        for binding in mode.bindings.values {
            bindings[binding.descriptionWithKeyNotation] = .string(binding.commands.shellOfCommandsDescription)
        }
        return OrderedJson.dict(["binding": .dict(bindings)])
    }
    return .dict(["mode": .dict(OrderedJson.JsonDict(uniqueKeysWithValues: modes))])
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
    config = newConfig
    configUrl = url
    registerHotkeys(for: activeMode) // A removed mode keeps its stale name and gets no hotkeys
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
