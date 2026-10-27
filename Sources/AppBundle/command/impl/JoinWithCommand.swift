import AppKit
import Common

struct JoinWithCommand: nonisolated Command {
    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var direction: CardinalDirection
    var windowId: UInt32? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var windowId: UInt32? = nil
        while let option = try a.nextOption() {
            switch option {
                case "--window-id": windowId = try a.windowId(of: option)
                default: throw .unknownOption(option)
            }
        }
        let result = Self(direction: try a.positional(), windowId: windowId)
        try a.end()
        return result
    }

    func run(_ cx: CmdContext) throws(CmdFail) {
        let currentWindow = try cx.window(windowId: windowId)
        guard let (parent, ownIndex) = currentWindow.closestParent(hasChildrenInDirection: direction, withLayout: nil) else {
            throw CmdFail("No windows in the specified direction")
        }
        let joinWithTarget = parent.children[ownIndex + direction.focusOffset]
        let prevBinding = joinWithTarget.unbindFromParent()
        let newParent = TilingContainer(
            parent: parent,
            weight: prevBinding.weight,
            parent.orientation.opposite,
            .tiles,
            index: prevBinding.index,
        )
        currentWindow.unbindFromParent()

        joinWithTarget.bind(to: newParent, index: 0)
        currentWindow.bind(to: newParent, index: direction.isPositive ? 0 : nil)
    }
}
