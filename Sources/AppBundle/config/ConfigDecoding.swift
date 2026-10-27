import Common
import TOMLDecoder

/// Every config decoder has this shape. `nil` means the value is unusable and the target keeps its default;
/// the reason is already recorded in the diagnostics. Only a collection whose elements are independent (modes,
/// bindings, window rules, force assignments, key and env tables) reports its bad elements and keeps the rest
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
    /// False if the value is unusable
    fileprivate let apply: (inout S, OrderedJson, ConfigBacktrace, inout Diagnostics) -> Bool

    private init(apply: @escaping (inout S, OrderedJson, ConfigBacktrace, inout Diagnostics) -> Bool) {
        self.apply = apply
    }

    init<T>(_ keyPath: WritableKeyPath<S, T>, _ decode: @escaping Decode<T>) {
        apply = { target, raw, path, d in
            guard let value = decode(raw, path, &d) else { return false }
            target[keyPath: keyPath] = value
            return true
        }
    }

    init<T>(_ keyPath: WritableKeyPath<S, T?>, _ decode: @escaping Decode<T>) {
        apply = { target, raw, path, d in
            guard let value = decode(raw, path, &d) else { return false }
            target[keyPath: keyPath] = value
            return true
        }
    }

    /// A nested table, decoded key by key on top of the field's current value
    init<T>(_ keyPath: WritableKeyPath<S, T>, _ fields: [String: Field<T>]) {
        apply = { target, raw, path, d in decodeTable(raw, into: &target[keyPath: keyPath], fields, path, &d) }
    }

    /// A known key that is decoded elsewhere
    static var ignored: Self { Field { _, _, _, _ in true } }
}

/// Decodes every key, even after an error. False if `raw` isn't a table, a key is unknown, or a value is unusable
@discardableResult
func decodeTable<S>(_ raw: OrderedJson, into target: inout S, _ fields: [String: Field<S>], _ path: ConfigBacktrace, _ d: inout Diagnostics) -> Bool {
    guard let table = decodeDict(raw, path, &d) else { return false }
    var isUsable = true
    for (key, value) in table {
        let path = path + .key(key)
        if let field = fields[key] {
            isUsable = field.apply(&target, value, path, &d) && isUsable
        } else {
            d.error(path, path.isRootKey ? "Unknown top-level key" : "Unknown key")
            isUsable = false
        }
    }
    return isUsable
}

/// The root table with sorted keys, or the syntax error. Values of unsupported types are reported and dropped
func decodeTomlRoot(_ rawToml: String, _ d: inout Diagnostics) -> ResOrStr<OrderedJson.JsonDict> {
    do {
        let dict: [String: Any] = try .init(try TOMLTable(source: rawToml))
        return .success(tomlToOrderedJson(dict, .emptyRoot, &d)?.asDictOrNil ?? [:])
    } catch {
        return .failure(error.description)
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
