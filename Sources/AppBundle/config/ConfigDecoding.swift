import Common
import TOMLDecoder

/// Every config decoder has this shape. `nil` means the value is unusable and the target keeps its default;
/// the reason is already recorded in the diagnostics
typealias Decode<T> = (OrderedJson, ConfigBacktrace, inout Diagnostics) -> T?

func expect<T>(_ type: TomlType, _ extract: @escaping (OrderedJson) -> T?) -> Decode<T> {
    { raw, path, d in
        if let value = extract(raw) { return value }
        d.typeMismatch(path, expected: type, actual: raw)
        return nil
    }
}

let decodeBool: Decode<Bool> = expect(.bool) { $0.asBoolOrNil }
let decodeInt: Decode<Int> = expect(.int) { $0.asIntOrNil }
let decodeString: Decode<String> = expect(.string) { $0.asStringOrNil }
let decodeArray: Decode<OrderedJson.JsonArray> = expect(.array) { $0.asArrayOrNil }
let decodeDict: Decode<OrderedJson.JsonDict> = expect(.table) { $0.asDictOrNil }

/// Decodes a string and converts it. A conversion failure is reported at the value's path
func decodeParsed<T>(_ convert: @escaping (String) -> ResOrStr<T>) -> Decode<T> {
    { raw, path, d in decodeString(raw, path, &d).flatMap { d.unwrap(convert($0), path) } }
}

/// How one key of a TOML table is decoded into a field of `S`
struct Field<S> {
    fileprivate let apply: (inout S, OrderedJson, ConfigBacktrace, inout Diagnostics) -> Void

    private init(apply: @escaping (inout S, OrderedJson, ConfigBacktrace, inout Diagnostics) -> Void) {
        self.apply = apply
    }

    init<T>(_ keyPath: WritableKeyPath<S, T>, _ decode: @escaping Decode<T>) {
        apply = { target, raw, path, d in
            if let value = decode(raw, path, &d) { target[keyPath: keyPath] = value }
        }
    }

    init<T>(_ keyPath: WritableKeyPath<S, T?>, _ decode: @escaping Decode<T>) {
        apply = { target, raw, path, d in
            if let value = decode(raw, path, &d) { target[keyPath: keyPath] = value }
        }
    }

    /// A nested table, decoded key by key on top of the field's current value
    init<T>(_ keyPath: WritableKeyPath<S, T>, _ fields: [String: Field<T>]) {
        apply = { target, raw, path, d in decodeTable(raw, into: &target[keyPath: keyPath], fields, path, &d) }
    }

    /// The key is decoded elsewhere (`check == nil`) or only produces diagnostics (deprecated keys)
    static func ignored(_ check: ((OrderedJson, ConfigBacktrace, inout Diagnostics) -> Void)? = nil) -> Self {
        Field { _, raw, path, d in check?(raw, path, &d) }
    }
}

func decodeTable<S>(_ raw: OrderedJson, into target: inout S, _ fields: [String: Field<S>], _ path: ConfigBacktrace, _ d: inout Diagnostics) {
    guard let table = decodeDict(raw, path, &d) else { return }
    for (key, value) in table {
        let path = path + .key(key)
        if let field = fields[key] {
            field.apply(&target, value, path, &d)
        } else {
            d.error(path, path.isRootKey ? "Unknown top-level key" : "Unknown key")
        }
    }
}

/// The root table with sorted keys. A syntax error is fatal. Values of unsupported types are reported and dropped
func decodeTomlRoot(_ rawToml: String, _ d: inout Diagnostics) -> OrderedJson.JsonDict {
    do {
        let dict: [String: Any] = try .init(try TOMLTable(source: rawToml))
        return tomlToOrderedJson(dict, .emptyRoot, &d)?.asDictOrNil ?? [:]
    } catch {
        d.fatal(error.description)
        return [:]
    }
}

private func tomlToOrderedJson(_ any: Any, _ path: ConfigBacktrace, _ d: inout Diagnostics) -> OrderedJson? {
    switch any {
        case let dict as [String: Any]:
            var json = OrderedJson.JsonDict()
            for (key, tomlValue) in dict.sortedEntries {
                json[key] = tomlToOrderedJson(tomlValue, path + .key(key), &d)
            }
            return .dict(json)
        case let array as [Any]:
            return .array(array.enumerated().compactMap { index, tomlValue in tomlToOrderedJson(tomlValue, path + .index(index), &d) })
        default:
            if let value = OrderedJson.newScalarOrNil(any) { return value }
            d.error(path, "Unsupported TOML type: \(type(of: any))")
            return nil
    }
}
