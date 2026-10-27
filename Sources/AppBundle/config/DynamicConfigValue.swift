import Common

struct PerMonitorValue<Value: Equatable>: Equatable {
    let description: MonitorDescription
    let value: Value
}
extension PerMonitorValue: Sendable where Value: Sendable {}

enum DynamicConfigValue<Value: Equatable>: Equatable {
    case constant(Value)
    case perMonitor([PerMonitorValue<Value>], default: Value)
}
extension DynamicConfigValue: Sendable where Value: Sendable {}

extension DynamicConfigValue {
    /// - Parameter sortedMonitors: evaluated only for per-monitor values
    func getValue(for monitor: MonitorInfo, sortedMonitors: @autoclosure () -> [MonitorInfo]) -> Value {
        switch self {
            case .constant(let value): return value
            case .perMonitor(let array, let defaultValue):
                let sortedMonitors = sortedMonitors()
                return array.first {
                    $0.description.resolveMonitor(sortedMonitors: sortedMonitors)?.rect.topLeftCorner == monitor.rect.topLeftCorner
                }?.value ?? defaultValue
        }
    }
}

let decodeDynamicInt: Decode<DynamicConfigValue<Int>> = { raw, path, d in
    if let value = raw.asIntOrNil { return .constant(value) }
    guard let array = raw.asArrayOrNil else {
        d.error(path, "Unsupported type: \(raw.tomlType), expected: Int or array")
        return nil
    }
    guard let defaultValue = array.last?.asIntOrNil else {
        d.error(path, array.isEmpty ? "The array must not be empty" : "The last item in the array must be of type Int")
        return nil
    }
    if array.count == 1 {
        d.error(path, "The array must contain at least one monitor pattern")
        return nil
    }
    let rules = array.dropLast().enumerated().compactMap { index, raw in decodePerMonitorValue(raw, path + .index(index), &d) }
    return .perMonitor(rules, default: defaultValue)
}

/// `{ monitor.<pattern> = <int> }`
private func decodePerMonitorValue(_ raw: OrderedJson, _ path: ConfigBacktrace, _ d: inout Diagnostics) -> PerMonitorValue<Int>? {
    var path = path
    guard let (_, monitor) = decodeSingleKeyTable(raw, expectedKey: "monitor", &path, &d),
          let (pattern, value) = decodeSingleKeyTable(monitor, &path, &d),
          let description = d.unwrap(parseMonitorDescription(pattern), path)
    else { return nil }
    guard let value = value.asIntOrNil else {
        d.error(path, "Expected type is 'Int'. But actual type is '\(value.tomlType)'")
        return nil
    }
    return PerMonitorValue(description: description, value: value)
}

/// The single key and its value. `path` is extended with the key
private func decodeSingleKeyTable(_ raw: OrderedJson, expectedKey: String? = nil, _ path: inout ConfigBacktrace, _ d: inout Diagnostics) -> (key: String, value: OrderedJson)? {
    guard let table = decodeDict(raw, path, &d) else { return nil }
    guard let (key, value) = table.elements.singleOrNil(), expectedKey == nil || expectedKey == key else {
        d.error(path, expectedKey.map { "The table is expected to have a single key '\($0)'" } ?? "The table is expected to have a single key")
        return nil
    }
    path = path + .key(key)
    return (key, value)
}
