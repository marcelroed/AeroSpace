/// Why words don't make a command, or a value (a workspace name, a regex, …) is invalid
public enum CmdParseError: Error, Equatable, Sendable, ExpressibleByStringInterpolation {
    case invalid(String)
    /// `-h` or `--help` asks for the help of the subcommand instead of a command
    case help(CmdKind)

    public init(stringLiteral message: String) { self = .invalid(message) }

    /// Where help isn't an answer, it's an error with the help as its message
    public var message: String {
        switch self {
            case .invalid(let message): message
            case .help(let kind): kind.help
        }
    }
}
