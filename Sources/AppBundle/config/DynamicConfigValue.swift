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
    @MainActor func getValue(for monitor: MonitorInfo, sortedMonitors: @autoclosure () -> [MonitorInfo]) -> Value {
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

/// A TOML scalar that a ``DynamicConfigValue`` can hold
protocol TomlScalar {
    static func fromTomlOrNil(_ raw: OrderedJson) -> Self?
}

extension Int: TomlScalar {
    static func fromTomlOrNil(_ raw: OrderedJson) -> Int? { raw.asIntOrNil }
}

func parseDynamicValue<T: TomlScalar>(
    _ raw: OrderedJson,
    ofType valueType: T.Type,
    _ fallback: T,
    _ backtrace: ConfigBacktrace,
    _ c: inout ConfigParserContext,
) -> DynamicConfigValue<T> {
    if let simpleValue = T.fromTomlOrNil(raw) {
        return .constant(simpleValue)
    } else if let array = raw.asArrayOrNil {
        if array.isEmpty {
            c.errors.append(.init(backtrace, "The array must not be empty"))
            return .constant(fallback)
        }

        guard let defaultValue = array.last.flatMap(T.fromTomlOrNil) else {
            c.errors.append(.init(backtrace, "The last item in the array must be of type \(T.self)"))
            return .constant(fallback)
        }

        if array.dropLast().isEmpty {
            c.errors.append(.init(backtrace, "The array must contain at least one monitor pattern"))
            return .constant(fallback)
        }

        let rules: [PerMonitorValue<T>] = parsePerMonitorValues(array.dropLast(), backtrace, &c)

        return .perMonitor(rules, default: defaultValue)
    } else {
        c.errors.append(.init(backtrace, "Unsupported type: \(raw.tomlType), expected: \(valueType) or array"))
        return .constant(fallback)
    }
}

func parsePerMonitorValues<T: TomlScalar>(_ array: OrderedJson.JsonArray, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> [PerMonitorValue<T>] {
    array.enumerated().compactMap { (index: Int, raw: OrderedJson) -> PerMonitorValue<T>? in
        var backtrace = backtrace + .index(index)

        guard let (key, value) = raw.unwrapTableWithSingleKey(expectedKey: "monitor", &backtrace)
            .flatMap({ $0.value.unwrapTableWithSingleKey(expectedKey: nil, &backtrace) })
            .getOrNil(appendErrorTo: &c.errors)
        else {
            return nil
        }

        let monitorDescriptionResult = parseMonitorDescription(.string(key), backtrace)

        guard let monitorDescription = monitorDescriptionResult.getOrNil(appendErrorTo: &c.errors) else { return nil }

        guard let value = T.fromTomlOrNil(value) else {
            c.errors.append(.init(backtrace, "Expected type is '\(T.self)'. But actual type is '\(value.tomlType)'"))
            return nil
        }

        return PerMonitorValue(description: monitorDescription, value: value)
    }
}
