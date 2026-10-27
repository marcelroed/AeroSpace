public struct MoveCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .move,
        flags: [
            "--window-id": windowIdSubArgParser(),
            "--boundaries": ArgParser(\.rawBoundaries, upcastArgParserFun(enumSubArg(Boundaries.self, placeholder: "<boundary>"))),
            "--boundaries-action": ArgParser(\.rawBoundariesAction, upcastArgParserFun(enumSubArg(WhenBoundariesCrossed.self, placeholder: "<action>"))),
            "--fail-if-fullscreen": trueBoolFlag(\.failIfFullscreen),
            "--fail-if-macos-native-fullscreen": trueBoolFlag(\.failIfMacosNativeFullscreen),
        ],
        posArgs: [newMandatoryPosArgParser(\.direction, enumPosArg(CardinalDirection.self), placeholder: CardinalDirection.unionLiteral)],
    )

    public var direction: Lateinit<CardinalDirection> = .uninitialized
    public var rawBoundaries: Boundaries? = nil
    public var rawBoundariesAction: WhenBoundariesCrossed? = nil
    public var failIfFullscreen: Bool = false
    public var failIfMacosNativeFullscreen: Bool = false

    public enum WhenBoundariesCrossed: String, CaseIterable, Equatable, Sendable {
        case stop = "stop"
        case fail = "fail"
        case createImplicitContainer = "create-implicit-container"
    }
}

extension MoveCmdArgs {
    public var boundaries: Boundaries { rawBoundaries ?? .workspace }
    public var boundariesAction: WhenBoundariesCrossed { rawBoundariesAction ?? .createImplicitContainer }
}
