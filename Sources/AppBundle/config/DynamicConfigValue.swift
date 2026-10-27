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

func parseDynamicValue(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> DynamicConfigValue<Int> {
    if let simpleValue = raw.asIntOrNil {
        return .constant(simpleValue)
    } else if let array = raw.asArrayOrNil {
        if array.isEmpty {
            c.errors.append(.init(backtrace, "The array must not be empty"))
            return .constant(0)
        }

        guard let defaultValue = array.last?.asIntOrNil else {
            c.errors.append(.init(backtrace, "The last item in the array must be of type Int"))
            return .constant(0)
        }

        if array.dropLast().isEmpty {
            c.errors.append(.init(backtrace, "The array must contain at least one monitor pattern"))
            return .constant(0)
        }

        let rules = parsePerMonitorValues(array.dropLast(), backtrace, &c)

        return .perMonitor(rules, default: defaultValue)
    } else {
        c.errors.append(.init(backtrace, "Unsupported type: \(raw.tomlType), expected: Int or array"))
        return .constant(0)
    }
}

private func parsePerMonitorValues(_ array: OrderedJson.JsonArray, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> [PerMonitorValue<Int>] {
    array.enumerated().compactMap { (index: Int, raw: OrderedJson) -> PerMonitorValue<Int>? in
        var backtrace = backtrace + .index(index)

        guard let (key, value) = raw.unwrapTableWithSingleKey(expectedKey: "monitor", &backtrace)
            .flatMap({ $0.value.unwrapTableWithSingleKey(expectedKey: nil, &backtrace) })
            .getOrNil(appendErrorTo: &c.errors)
        else {
            return nil
        }

        let monitorDescriptionResult = parseMonitorDescription(.string(key), backtrace)

        guard let monitorDescription = monitorDescriptionResult.getOrNil(appendErrorTo: &c.errors) else { return nil }

        guard let value = value.asIntOrNil else {
            c.errors.append(.init(backtrace, "Expected type is 'Int'. But actual type is '\(value.tomlType)'"))
            return nil
        }

        return PerMonitorValue(description: monitorDescription, value: value)
    }
}
