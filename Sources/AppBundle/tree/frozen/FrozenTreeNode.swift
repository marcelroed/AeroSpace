import AppKit
import Common

enum FrozenTreeNode: Sendable {
    case container(FrozenContainer)
    case window(FrozenWindow)
}

struct FrozenContainer: Sendable {
    let children: [FrozenTreeNode]
    let layout: Layout
    let orientation: Orientation
    let weight: CGFloat

    init(_ container: TilingContainer) {
        children = container.children.map {
            switch $0 {
                case let w as Window: .window(FrozenWindow(w))
                case let c as TilingContainer: .container(FrozenContainer(c))
                default: dieT("\($0.prettyDescription) can't be a child of a tiling container")
            }
        }
        layout = container.layout
        orientation = container.orientation
        weight = getWeightOrNil(container) ?? 1
    }
}

struct FrozenWindow: Sendable {
    let id: WindowId
    let weight: CGFloat

    init(_ window: Window) {
        id = window.windowId
        weight = getWeightOrNil(window) ?? 1
    }
}

private func getWeightOrNil(_ node: TreeNode) -> CGFloat? {
    ((node.parent as? TilingContainer)?.orientation).map { node.getWeight($0) }
}
