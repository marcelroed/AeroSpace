import AppKit
import Common

struct ResizeCommand: Command {
    let args: ResizeCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }

        let candidates = target.windowOrNil?.parentsWithSelf
            .filter { ($0.parent as? TilingContainer)?.layout == .tiles }
            ?? []

        // All candidates have a TilingContainer parent, so for .smart, node is candidates.first
        let orientation: Orientation? = switch args.dimension.val {
            case .width: .h
            case .height: .v
            case .smart: (candidates.first?.parent as? TilingContainer)?.orientation
            case .smartOpposite: (candidates.first?.parent as? TilingContainer)?.orientation.opposite
        }
        let node = candidates.first(where: { ($0.parent as? TilingContainer)?.orientation == orientation })
        // node was picked by its parent's orientation, so parent.orientation == orientation
        guard let node, let parent = node.parent as? TilingContainer else {
            guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
            if window.isFloating {
                return .fail(io.err("resize command doesn't support floating windows yet https://github.com/nikitabobko/AeroSpace/issues/9"))
            }
            let container = switch orientation {
                case .h: "horizontal tiles container"
                case .v: "vertical tiles container"
                case nil: "tiles container"
            }
            return .fail(io.err("Can't resize: the window isn't inside a \(container)"))
        }
        let diff: CGFloat = switch args.units.val {
            case .set(let unit): CGFloat(unit) - node.getWeight(parent.orientation)
            case .add(let unit): CGFloat(unit)
            case .subtract(let unit): -CGFloat(unit)
        }

        guard let childDiff = diff.div(parent.children.count - 1) else {
            return .fail(io.err("Can't resize: there are no other tiling windows \(parent.orientation == .h ? "to the left or right" : "above or below")"))
        }
        for child in parent.children where child != node {
            child.setWeight(parent.orientation, child.getWeight(parent.orientation) - childDiff)
        }

        node.setWeight(parent.orientation, node.getWeight(parent.orientation) + diff)
        return .succ
    }
}
