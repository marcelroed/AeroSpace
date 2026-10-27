import AppKit
import Common

struct ResizeCommand: nonisolated Command {
    nonisolated enum Dimension: String, CaseIterable, Equatable, Sendable {
        case width, height, smart
        case smartOpposite = "smart-opposite"
    }

    nonisolated enum Units: Equatable, Sendable {
        case set(UInt)
        case add(UInt)
        case subtract(UInt)

        /// `[+|-]<number>`: exactly one optional sign
        static func parse(_ raw: String) throws(CmdParseError) -> Self {
            let digits = raw.starts(with: "+") || raw.starts(with: "-") ? raw.dropFirst() : raw[...]
            // UInt(...) accepts a sign too. Check the first char, so that the number has exactly one optional sign
            guard digits.first?.isNumber == true, let number = UInt(digits) else { throw "<number> argument must be a number" }
            return switch raw.first {
                case "+": .add(number)
                case "-": .subtract(number)
                default: .set(number)
            }
        }
    }

    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var dimension: Dimension
    var units: Units
    var windowId: UInt32? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var windowId: UInt32? = nil
        while let option = try a.nextOption() {
            switch option {
                case "--window-id": windowId = try a.windowId(of: option)
                default: throw .unknownOption(option)
            }
        }
        let dimension: Dimension = try parseEnum(a.positional("(smart|smart-opposite|width|height)"))
        let units = try Units.parse(a.positional("[+|-]<number>"))
        try a.end()
        return Self(dimension: dimension, units: units, windowId: windowId)
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let target = try cx.target(windowId: windowId)

        let candidates = target.windowOrNil?.parentsWithSelf
            .filter { ($0.parent as? TilingContainer)?.layout == .tiles }
            ?? []

        // All candidates have a TilingContainer parent, so for .smart, node is candidates.first
        let orientation: Orientation? = switch dimension {
            case .width: .h
            case .height: .v
            case .smart: (candidates.first?.parent as? TilingContainer)?.orientation
            case .smartOpposite: (candidates.first?.parent as? TilingContainer)?.orientation.opposite
        }
        let node = candidates.first(where: { ($0.parent as? TilingContainer)?.orientation == orientation })
        // node was picked by its parent's orientation, so parent.orientation == orientation
        guard let node, let parent = node.parent as? TilingContainer else {
            guard let window = target.windowOrNil else { throw CmdFail(noWindowIsFocused) }
            if window.isFloating {
                throw CmdFail("resize command doesn't support floating windows yet https://github.com/nikitabobko/AeroSpace/issues/9")
            }
            let container = switch orientation {
                case .h: "horizontal tiles container"
                case .v: "vertical tiles container"
                case nil: "tiles container"
            }
            throw CmdFail("Can't resize: the window isn't inside a \(container)")
        }
        let diff: CGFloat = switch units {
            case .set(let unit): CGFloat(unit) - node.getWeight(parent.orientation)
            case .add(let unit): CGFloat(unit)
            case .subtract(let unit): -CGFloat(unit)
        }

        guard let childDiff = diff.div(parent.children.count - 1) else {
            throw CmdFail("Can't resize: there are no other tiling windows \(parent.orientation == .h ? "to the left or right" : "above or below")")
        }
        for child in parent.children where child != node {
            child.setWeight(parent.orientation, child.getWeight(parent.orientation) - childDiff)
        }

        node.setWeight(parent.orientation, node.getWeight(parent.orientation) + diff)
    }
}
