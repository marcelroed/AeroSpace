public func parseCmdArgs(_ args: StrArrSlice) -> ParsedCmd<any CmdArgs> {
    let subcommand = args.first ?? ""
    if subcommand.isEmpty {
        return .failure("Can't parse empty string command", EXIT_CODE_TWO)
    }
    if let subcommandParser = subcommandParsers[subcommand] {
        return subcommandParser.parse(args.slice(1...).orDie())
    } else {
        return .failure("Unrecognized subcommand '\(subcommand)'", EXIT_CODE_TWO)
    }
}

public protocol CmdArgs:
    ConvenienceMutable,
    Equatable,
    CustomStringConvertible,
    AeroAny,
    Sendable
{
    associatedtype ExitCodeType: ExitCode = BinaryExitCode
    static var parser: CmdParser<Self> { get }
    var commonState: CmdArgsCommonState { get set }
}

public struct CmdArgsCommonState: ConvenienceMutable, Equatable, Sendable {
    let rawArgsForStrRepr: EquatableNoop<StrArrSlice>
    var windowId: UInt32? = nil
    var workspaceName: WorkspaceName? = nil
    public var explicitStdinFlag: Bool? = nil

    public init(_ raw: StrArrSlice) { rawArgsForStrRepr = .init(raw) }
}

extension CmdArgs {
    public var windowId: UInt32? {
        get { commonState.windowId }
        set(value) { commonState.windowId = value }
    }

    public var workspaceName: WorkspaceName? {
        get { commonState.workspaceName }
        set(value) { commonState.workspaceName = value }
    }

    public var failExitCode: Int32 { ExitCodeType.fail.rawValue }

    public func equals(_ other: any CmdArgs) -> Bool { // My brain is cursed with Java
        (other as? Self).flatMap { self == $0 } ?? false
    }

    public var description: String {
        ([Self.parser.kind.rawValue] + commonState.rawArgsForStrRepr.value.toArray()).joinArgs()
    }
}

public struct CmdParser<Root>: Sendable {
    public let kind: CmdKind
    var flags: [String: any ArgParserProtocol<SubArgParserInput, Root, ()>] = [:]
    var posArgs: [any ArgParserProtocol<PosArgParserInput, Root, PosArgParserContext>] = []
    var conflictingOptions: [Set<String>] = []
    /// Whether args like `-10` are positional arguments rather than unknown flags
    var negativeNumbersArePositional = false
}
