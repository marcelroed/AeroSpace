import AppKit
import Common

struct ConfigCommand: Command {
    let args: ConfigCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        switch args.mode {
            case .getKey(let key):
                return getKey(io, args: args, key: key)
            case .majorKeys:
                let out = """
                    .
                    mode
                    \(config.modes.keys.sorted().map { "mode.\($0).binding" }.joined(separator: "\n"))
                    """
                return .succ(io.out(out))
            case .allKeys:
                let configMap = buildConfigMap()
                var allKeys: [String] = []
                configMap.dumpAllKeysRecursive(path: ".", result: &allKeys)
                return .succ(io.out(allKeys.joined(separator: "\n")))
            case .configPath:
                return .succ(io.out(configUrl.absoluteURL.path))
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

/// `buildConfigMap()` contains only dicts and strings, and `--keys` turns a dict into an array of strings
private func getKey(_ io: CmdIo, args: ConfigCmdArgs, key: String) -> BinaryExitCode {
    guard let keyPath = key.toKeyPath().getOrNil(appendErrorTo: &io.stderr) else { return .fail }
    guard var configMap = buildConfigMap().find(keyPath: keyPath.slice).getOrNil(appendErrorTo: &io.stderr) else { return .fail }
    if args.keys {
        guard let dict = configMap.asDictOrNil else {
            return .fail(io.err("--keys flag cannot be applied to scalar object '\(configMap.scalarDescription.orDie())'"))
        }
        configMap = .array(dict.keys.sorted().map { .string($0) })
    }
    if args.json {
        return switch JSONEncoder.aeroSpaceDefault.encodeToString(configMap) {
            case let json?: .succ(io.out(json))
            case nil: .fail(io.err("Can't convert json Data to String"))
        }
    }
    return switch configMap {
        case .dict:
            .fail(io.err("Complicated objects can be printed only with --json flag. Alternatively, you can try to inspect keys of the object with --keys flag"))
        case .array(let keys): .succ(io.out(keys.compactMap(\.asStringOrNil).sorted().joined(separator: "\n")))
        case .string, .int, .bool, .null: .succ(io.out(configMap.scalarDescription.orDie()))
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
    var shellOfCommandsDescription: String { buildDescription { $0.args.description } }
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
