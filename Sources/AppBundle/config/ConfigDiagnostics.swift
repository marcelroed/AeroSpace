import Common

struct ConfigParseDiagnostic: Equatable, Sendable {
    let backtrace: ConfigBacktrace
    let message: String

    init(_ backtrace: ConfigBacktrace, _ message: String) {
        check(!message.isEmpty)
        self.backtrace = backtrace
        self.message = message
    }

    var description: String {
        let path = backtrace.description
        return path.isEmpty ? "[ERROR] \(message)" : "[ERROR] \(path): \(message)"
    }
}

/// The single sink every decoder reports into. The append order is the order users see
struct Diagnostics: Sendable {
    private(set) var errors: [ConfigParseDiagnostic] = []

    mutating func error(_ path: ConfigBacktrace, _ message: String) {
        errors.append(ConfigParseDiagnostic(path, message))
    }

    /// The parsed value, or nil after reporting the parse error at `path`
    mutating func parsed<T>(_ path: ConfigBacktrace, _ parse: () throws(CmdParseError) -> T) -> T? {
        do {
            return try parse()
        } catch {
            self.error(path, error.message)
            return nil
        }
    }

    /// "Expected type is 'Int'. …" or "Expected types are 'String' or 'Array'. …"
    mutating func typeMismatch(_ path: ConfigBacktrace, expected: TomlType..., actual: OrderedJson) {
        let types = expected.map(\.rawValue.singleQuoted).joined(separator: " or ")
        let expectedTypes = expected.count == 1 ? "type is \(types)" : "types are \(types)"
        error(path, "Expected \(expectedTypes). But actual type is \(actual.tomlType.rawValue.singleQuoted)")
    }
}

struct ConfigBacktrace: CustomStringConvertible, Equatable, Sendable {
    private var path: [TomlBacktraceItem] = []

    static func rootKey(_ key: String) -> Self { Self(path: [.key(key)]) }
    static let emptyRoot: Self = Self()

    /// Keys are written like in TOML: `gaps.outer.left[0].monitor."built-in retina"`
    var description: String {
        var result = ""
        for (i, elem) in path.enumerated() {
            switch elem {
                case .key(let rootKey) where i == 0: result += tomlKey(rootKey)
                case .key(let key): result += "." + tomlKey(key)
                case .index(let index): result += "[\(index)]"
            }
        }
        return result
    }

    var isRootKey: Bool {
        if case .key? = path.singleOrNil() { true } else { false }
    }

    static func + (lhs: consuming Self, rhs: TomlBacktraceItem) -> Self {
        lhs.path.append(rhs)
        return lhs
    }
}

/// A bare key as is, any other key quoted
private func tomlKey(_ key: String) -> String {
    let isBare = !key.isEmpty && key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    if isBare { return key }
    return "\"" + key.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"") + "\""
}

enum TomlBacktraceItem: Equatable, Sendable {
    case key(String)
    case index(Int)
}
