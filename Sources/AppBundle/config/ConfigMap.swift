import Common
import OrderedCollections

/// What `aerospace config --get` shows: tables of modes and bindings, and the bindings' commands as strings
enum ConfigMap: Equatable {
    case table(OrderedDictionary<String, ConfigMap>)
    case string(String)

    var json: OrderedJson {
        switch self {
            case .table(let table): .dict(table.mapValues(\.json))
            case .string(let string): .string(string)
        }
    }

    func find(keyPath: StrArrSlice) -> Result<ConfigMap, String> {
        guard let key = keyPath.first else { return .success(self) }
        switch self {
            case .string(let string):
                return .failure("Can't dereference scalar value '\(string)'")
            case .table(let table):
                guard let value = table[key] else { return .failure("No value at key token '\(key)'") }
                return value.find(keyPath: keyPath.slice(1...).orDie())
        }
    }

    func dumpAllKeysRecursive(path: String, result: inout [String]) {
        result.append(path)
        guard case .table(let table) = self else { return }
        for (key, value) in table.sorted(by: { $0.key < $1.key }) {
            value.dumpAllKeysRecursive(path: path == "." ? key : path + "." + key, result: &result)
        }
    }
}

func buildConfigMap() -> ConfigMap {
    let modes = config.modes.mapValues { mode in
        var bindings: OrderedDictionary<String, ConfigMap> = [:]
        for binding in mode.bindings.values {
            bindings[binding.descriptionWithKeyNotation] = .string(binding.commands.shellOfCommandsDescription)
        }
        return ConfigMap.table(["binding": .table(bindings)])
    }
    return .table(["mode": .table(OrderedDictionary(uniqueKeysWithValues: modes))])
}
