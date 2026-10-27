public struct FocusCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    fileprivate init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .focus,
        flags: [
            "--ignore-floating": falseBoolFlag(\.floatingAsTiling),
            "--window-id": windowIdSubArgParser(),
            "--dfs-index": singleValueSubArgParser(\.dfsIndex, "<dfs-index>", parseUInt32),

            "--boundaries": ArgParser(\.rawBoundaries, upcastArgParserFun(enumSubArg(Boundaries.self, placeholder: "<boundary>"))),
            "--boundaries-action": ArgParser(\.rawBoundariesAction, upcastArgParserFun(enumSubArg(WhenBoundariesCrossed.self, placeholder: "<action>"))),
            "--fail-if-fullscreen": trueBoolFlag(\.failIfFullscreen),
            "--fail-if-macos-native-fullscreen": trueBoolFlag(\.failIfMacosNativeFullscreen),
            "--wrap-around": trueBoolFlag(\.wrapAroundAlias),
        ],
        posArgs: [ArgParser(\.cardinalOrDfsDirection, upcastArgParserFun(enumPosArg(CardinalOrDfsDirection.self)))],
        conflictingOptions: [
            ["--wrap-around", "--boundaries-action"],
            ["--wrap-around", "--boundaries"],
        ],
    )

    public var rawBoundaries: Boundaries? = nil // todo cover boundaries wrapping with tests
    public var rawBoundariesAction: WhenBoundariesCrossed? = nil
    public var failIfFullscreen: Bool = false
    public var failIfMacosNativeFullscreen: Bool = false
    fileprivate var wrapAroundAlias: Bool = false
    public var dfsIndex: UInt32? = nil
    public var cardinalOrDfsDirection: CardinalOrDfsDirection? = nil
    public var floatingAsTiling: Bool = true

    public init(rawArgs: StrArrSlice, cardinalOrDfsDirection: CardinalOrDfsDirection) {
        self.commonState = .init(rawArgs)
        self.cardinalOrDfsDirection = cardinalOrDfsDirection
    }

    public init(rawArgs: StrArrSlice, windowId: UInt32) {
        self.commonState = .init(rawArgs)
        self.windowId = windowId
    }

    public init(rawArgs: StrArrSlice, dfsIndex: UInt32) {
        self.commonState = .init(rawArgs)
        self.dfsIndex = dfsIndex
    }

    public enum WhenBoundariesCrossed: String, CaseIterable, Equatable, Sendable {
        case stop = "stop"
        case fail = "fail"
        case wrapAroundTheWorkspace = "wrap-around-the-workspace"
        case wrapAroundAllMonitors = "wrap-around-all-monitors"
    }
}

public enum Boundaries: String, CaseIterable, Equatable, Sendable { // focus and move --boundaries
    case workspace
    case allMonitorsOuterFrame = "all-monitors-outer-frame"
}

public enum FocusCmdTarget {
    case direction(CardinalDirection)
    case windowId(UInt32)
    case dfsIndex(UInt32)
    case dfsRelative(DfsNextPrev)

    var isDfsRelative: Bool {
        switch self {
            case .dfsRelative: true
            default: false
        }
    }
}

extension FocusCmdArgs {
    public var target: FocusCmdTarget {
        if let cardinalOrDfsDirection {
            return switch cardinalOrDfsDirection {
                case .direction(let dir): .direction(dir)
                case .dfsRelative(let nextPrev): .dfsRelative(nextPrev)
            }
        }
        if let windowId {
            return .windowId(windowId)
        }
        if let dfsIndex {
            return .dfsIndex(dfsIndex)
        }
        die("Parser invariants are broken")
    }

    public var boundaries: Boundaries { rawBoundaries ?? .workspace }
    public var boundariesAction: WhenBoundariesCrossed {
        wrapAroundAlias ? .wrapAroundTheWorkspace : (rawBoundariesAction ?? .stop)
    }
}

func parseFocusCmdArgs(_ args: StrArrSlice) -> ParsedCmd<FocusCmdArgs> {
    return parseSpecificCmdArgs(FocusCmdArgs(rawArgs: args), args)
        .filterNot("\(Boundaries.workspace.rawValue) and \(FocusCmdArgs.WhenBoundariesCrossed.wrapAroundAllMonitors.rawValue) is an invalid combination of values") {
            $0.boundaries == .workspace && $0.boundariesAction == .wrapAroundAllMonitors
        }
        .filter("Mandatory argument is missing. \(CardinalOrDfsDirection.unionLiteral), --window-id or --dfs-index is required") {
            $0.cardinalOrDfsDirection != nil || $0.windowId != nil || $0.dfsIndex != nil
        }
        .filter("--window-id is incompatible with other options") { raw in
            raw.windowId.map { raw == FocusCmdArgs(rawArgs: args, windowId: $0) } ?? true
        }
        .filter("--dfs-index is incompatible with other options") { raw in
            raw.dfsIndex.map { raw == FocusCmdArgs(rawArgs: args, dfsIndex: $0) } ?? true
        }
        .filter("--fail-if-fullscreen/--fail-if-macos-native-fullscreen require using (left|down|up|right) argument") {
            if !$0.failIfFullscreen && !$0.failIfMacosNativeFullscreen {
                return true
            }
            return switch $0.target {
                case .direction: true
                case .dfsIndex, .dfsRelative, .windowId: false
            }
        }
        .filter("(dfs-next|dfs-prev) only supports --boundaries workspace") {
            $0.target.isDfsRelative.implies($0.boundaries == .workspace)
        }
}
