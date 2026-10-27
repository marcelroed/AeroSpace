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
    /// TOML syntax error, unreadable or ambiguous file: the config must not be applied
    private(set) var isFatal = false

    mutating func error(_ path: ConfigBacktrace, _ message: String) {
        errors.append(ConfigParseDiagnostic(path, message))
    }

    mutating func fatal(_ message: String) {
        isFatal = true
        error(.emptyRoot, message)
    }

    /// The success value, or nil after reporting the failure at `path`
    mutating func unwrap<T>(_ result: ResOrStr<T>, _ path: ConfigBacktrace) -> T? {
        switch result {
            case .success(let value): return value
            case .failure(let message):
                error(path, message)
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

    var description: String {
        var result = ""
        for (i, elem) in path.enumerated() {
            switch elem {
                case .key(let rootKey) where i == 0: result += rootKey
                case .key(let key): result += ".\(key)"
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

enum TomlBacktraceItem: Equatable, Sendable {
    case key(String)
    case index(Int)
}
