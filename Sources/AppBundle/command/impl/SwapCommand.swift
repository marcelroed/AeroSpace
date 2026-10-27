import AppKit
import Common

struct SwapCommand: nonisolated Command {
    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var target: CardinalOrDfsDirection
    var swapFocus = false
    var wrapAround = false
    var windowId: UInt32? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var swapFocus = false
        var wrapAround = false
        var windowId: UInt32? = nil
        while let option = try a.nextOption() {
            switch option {
                case "--swap-focus": swapFocus = true
                case "--wrap-around": wrapAround = true
                case "--window-id": windowId = try a.windowId(of: option)
                default: throw .unknownOption(option)
            }
        }
        let target: CardinalOrDfsDirection = try a.positional()
        try a.end()
        return Self(target: target, swapFocus: swapFocus, wrapAround: wrapAround, windowId: windowId)
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let liveFocus = try cx.target(windowId: windowId)
        guard let currentWindow = liveFocus.windowOrNil else { throw CmdFail(noWindowIsFocused) }

        let targetWindow: Window?
        switch target {
            case .direction(let direction):
                switch currentWindow.closestParent(hasChildrenInDirection: direction, withLayout: nil) {
                    case let (parent, ownIndex)?:
                        targetWindow = parent.children[ownIndex + direction.focusOffset].findLeafWindowRecursive(snappedTo: direction.opposite)
                    case nil where wrapAround:
                        targetWindow = liveFocus.workspace.findLeafWindowRecursive(snappedTo: direction.opposite)
                    case nil:
                        throw .silent
                }
            case .dfsRelative(let nextPrev):
                let windows = liveFocus.workspace.rootTilingContainer.allLeafWindowsRecursive
                guard let currentIndex = windows.firstIndex(where: { $0 == liveFocus.windowOrNil }) else { throw .silent }
                let targetIndex = currentIndex + nextPrev.indexOffset
                targetWindow = wrapAround ? windows.get(wrappingIndex: targetIndex) : windows.getOrNil(atIndex: targetIndex)
        }

        guard let targetWindow else { throw .silent }

        swapWindows(mruDominant: currentWindow, targetWindow)

        if swapFocus && !targetWindow.focusWindow() { throw .silent }
    }
}
