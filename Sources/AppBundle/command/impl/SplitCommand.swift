import AppKit
import Common

struct SplitCommand: nonisolated Command {
    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var arg: SplitArg
    var windowId: UInt32? = nil

    nonisolated enum SplitArg: String, CaseIterable, Sendable {
        case horizontal, vertical, opposite
    }

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var windowId: UInt32? = nil
        while let option = try a.nextOption() {
            switch option {
                case "--window-id": windowId = try a.windowId(of: option)
                default: throw .unknownOption(option)
            }
        }
        let result = Self(arg: try a.positional(), windowId: windowId)
        try a.end()
        return result
    }

    func run(_ cx: CmdContext) throws(CmdFail) {
        if config.enableNormalizationFlattenContainers {
            throw CmdFail("'split' has no effect when 'enable-normalization-flatten-containers' normalization enabled. My recommendation: keep the normalizations enabled, and prefer 'join-with' over 'split'.")
        }
        let window = try cx.window(windowId: windowId)
        switch window.placement {
            case .floating:
                // Nothing to do for floating and macOS native fullscreen windows
                throw CmdFail("Can't split floating windows")
            case .tiling(let parent):
                let orientation: Orientation = switch arg {
                    case .vertical: .v
                    case .horizontal: .h
                    case .opposite: parent.orientation.opposite
                }
                if parent.children.count == 1 {
                    parent.changeOrientation(orientation)
                } else {
                    let data = window.unbindFromParent()
                    let newParent = TilingContainer(
                        parent: parent,
                        weight: data.weight,
                        orientation,
                        .tiles,
                        index: data.index,
                    )
                    window.bind(to: newParent, index: 0)
                }
                return
            case .macosMinimized, .macosFullscreen, .macosHiddenApp:
                throw CmdFail("Can't split macos fullscreen, minimized windows and windows of hidden apps. This behavior may change in the future")
            case .macosPopup, nil:
                throw CmdFail(bugPrompt()) // Impossible
        }
    }
}
