import AppKit
import Common

struct SplitCommand: Command {
    let args: SplitCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        if config.enableNormalizationFlattenContainers {
            return .fail(io.err("'split' has no effect when 'enable-normalization-flatten-containers' normalization enabled. My recommendation: keep the normalizations enabled, and prefer 'join-with' over 'split'."))
        }
        guard let window = args.resolveWindowOrReportError(env, io) else { return .fail }
        switch window.placement {
            case .floating:
                // Nothing to do for floating and macOS native fullscreen windows
                return .fail(io.err("Can't split floating windows"))
            case .tiling(let parent):
                let orientation: Orientation = switch args.arg.val {
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
                return .succ
            case .macosMinimized, .macosFullscreen, .macosHiddenApp:
                return .fail(io.err("Can't split macos fullscreen, minimized windows and windows of hidden apps. This behavior may change in the future"))
            case .macosPopup, nil:
                return .fail(io.err(bugPrompt())) // Impossible
        }
    }
}
