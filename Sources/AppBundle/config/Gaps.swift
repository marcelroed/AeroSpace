import Common

typealias Gaps = GapsOf<DynamicConfigValue<Int>>
typealias ResolvedGaps = GapsOf<Int>

struct GapsOf<V: Equatable>: Equatable {
    var inner: Inner
    var outer: Outer

    struct Inner: Equatable {
        var vertical: V
        var horizontal: V

        func get(_ orientation: Orientation) -> V {
            orientation == .h ? horizontal : vertical
        }
    }

    struct Outer: Equatable {
        var left: V
        var bottom: V
        var top: V
        var right: V
    }

    func map<R>(_ transform: (V) -> R) -> GapsOf<R> {
        GapsOf<R>(
            inner: .init(vertical: transform(inner.vertical), horizontal: transform(inner.horizontal)),
            outer: .init(left: transform(outer.left), bottom: transform(outer.bottom), top: transform(outer.top), right: transform(outer.right)),
        )
    }
}

extension GapsOf where V: ExpressibleByIntegerLiteral {
    static var zero: Self { Self(inner: .zero, outer: .init(left: 0, bottom: 0, top: 0, right: 0)) }
}

extension GapsOf.Inner where V: ExpressibleByIntegerLiteral {
    static var zero: Self { Self(vertical: 0, horizontal: 0) }
}

extension ResolvedGaps {
    init(gaps: Gaps, monitor: MonitorInfo) {
        // Query the monitors at most once, and only if some of the gaps are per-monitor
        lazy var sortedMonitors = sortedMonitorInfos
        self = gaps.map { $0.getValue(for: monitor, sortedMonitors: sortedMonitors) }
    }
}

struct PerMonitorValue<Value: Equatable>: Equatable {
    let description: MonitorDescription
    let value: Value
}

/// A value that can differ per monitor: the first rule whose monitor matches wins, otherwise `default`
struct DynamicConfigValue<Value: Equatable>: Equatable {
    var rules: [PerMonitorValue<Value>]
    var `default`: Value

    static func constant(_ value: Value) -> Self { Self(rules: [], default: value) }
    static func perMonitor(_ rules: [PerMonitorValue<Value>], default: Value) -> Self { Self(rules: rules, default: `default`) }

    /// - Parameter sortedMonitors: evaluated only for per-monitor values
    func getValue(for monitor: MonitorInfo, sortedMonitors: @autoclosure () -> [MonitorInfo]) -> Value {
        rules.first {
            $0.description.resolveMonitor(sortedMonitors: sortedMonitors())?.rect.topLeftCorner == monitor.rect.topLeftCorner
        }?.value ?? `default`
    }
}

extension DynamicConfigValue: ExpressibleByIntegerLiteral where Value == Int {
    init(integerLiteral value: Int) { self = .constant(value) }
}

let gapsFields: [String: Field<Gaps>] = [
    "inner": Field(\.inner, [
        "vertical": Field(\.vertical, decodeDynamicInt),
        "horizontal": Field(\.horizontal, decodeDynamicInt),
    ]),
    "outer": Field(\.outer, [
        "left": Field(\.left, decodeDynamicInt),
        "bottom": Field(\.bottom, decodeDynamicInt),
        "top": Field(\.top, decodeDynamicInt),
        "right": Field(\.right, decodeDynamicInt),
    ]),
]

/// An Int, or per-monitor rules followed by the default Int. Unusable if any rule is. `[n]` is the constant `n`
let decodeDynamicInt: Decode<DynamicConfigValue<Int>> = { raw, path, d in
    if let value = raw.asIntOrNil { return .constant(value) }
    guard let array = raw.asArrayOrNil else {
        d.typeMismatch(path, expected: .int, .array, actual: raw)
        return nil
    }
    guard let defaultValue = array.last?.asIntOrNil else {
        d.error(path, array.isEmpty ? "The array must not be empty" : "The last item in the array must be of type Int")
        return nil
    }
    let rules = array.dropLast().enumerated().map { index, raw in decodePerMonitorValue(raw, path + .index(index), &d) }
    return allOrNil(rules).map { .perMonitor($0, default: defaultValue) }
}

/// `{ monitor.<pattern> = <int> }`
private func decodePerMonitorValue(_ raw: OrderedJson, _ path: ConfigBacktrace, _ d: inout Diagnostics) -> PerMonitorValue<Int>? {
    var path = path
    guard let (_, monitor) = decodeSingleKeyTable(raw, expectedKey: "monitor", &path, &d),
          let (pattern, value) = decodeSingleKeyTable(monitor, &path, &d),
          let description = d.unwrap(parseMonitorDescription(pattern), path)
    else { return nil }
    guard let value = value.asIntOrNil else {
        d.typeMismatch(path, expected: .int, actual: value)
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
