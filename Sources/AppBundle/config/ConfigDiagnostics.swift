import Common

struct ConfigParseDiagnostic: Equatable, Sendable {
    let backtrace: ConfigBacktrace
    let message: String

    init(_ backtrace: ConfigBacktrace, _ message: String) {
        check(!message.isEmpty)
        self.backtrace = backtrace
        self.message = message
    }

    func description(_ severity: Severity) -> String {
        let path = backtrace.description
        return path.isEmpty ? "[\(severity.rawValue)] \(message)" : "[\(severity.rawValue)] \(path): \(message)"
    }

    enum Severity: String {
        case warning = "WARNING"
        case error = "ERROR"
    }
}

/// The single sink every decoder reports into. The append order is the order users see
struct Diagnostics: Sendable {
    private(set) var errors: [ConfigParseDiagnostic] = []
    private(set) var warnings: [ConfigParseDiagnostic] = []
    /// TOML syntax error, unreadable or ambiguous file: the config must not be applied
    private(set) var isFatal = false

    mutating func error(_ path: ConfigBacktrace, _ message: String) {
        errors.append(ConfigParseDiagnostic(path, message))
    }

    mutating func warning(_ path: ConfigBacktrace, _ message: String) {
        warnings.append(ConfigParseDiagnostic(path, message))
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

    mutating func typeMismatch(_ path: ConfigBacktrace, expected: TomlType, actual: OrderedJson) {
        error(path, "Expected type is \(expected.rawValue.singleQuoted). But actual type is \(actual.tomlType.rawValue.singleQuoted)")
    }

    /// Unlike the single-type message, prints the lowercase case names ('string' or 'array'). Tests pin both formats
    mutating func typeMismatch(_ path: ConfigBacktrace, expected: [TomlType], actual: OrderedJson) {
        error(path, "Expected types are \(expected.map { "'\($0)'" }.joined(separator: " or ")). But actual type is '\(actual.tomlType)'")
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
