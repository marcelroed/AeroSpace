import AppKit
import Common

extension TreeNode {
    private func collectLeafWindows(into result: inout [Window]) {
        if let window = self as? Window {
            result.append(window)
        }
        for child in children {
            child.collectLeafWindows(into: &result)
        }
    }
    var allLeafWindowsRecursive: [Window] {
        var result: [Window] = []
        collectLeafWindows(into: &result)
        return result
    }

    var nodeWorkspace: Workspace? {
        self as? Workspace ?? parent?.nodeWorkspace
    }

    /// nil for the minimized and popup windows: their containers are roots, like workspaces
    var nodeMonitor: MonitorInfo? { nodeWorkspace?.workspaceMonitor }

    /// Follows the most recent children down to a window. nil if that path ends in a container without windows
    var mostRecentWindowRecursive: Window? {
        self as? Window ?? mostRecentChild?.mostRecentWindowRecursive
    }

    var anyLeafWindowRecursive: Window? {
        if let window = self as? Window {
            return window
        }
        for child in children {
            if let window = child.anyLeafWindowRecursive {
                return window
            }
        }
        return nil
    }

    // Doesn't contain at least one window
    var isEffectivelyEmpty: Bool {
        anyLeafWindowRecursive == nil
    }

    var hWeight: CGFloat {
        get { getWeight(.h) }
        set { setWeight(.h, newValue) }
    }

    var vWeight: CGFloat {
        get { getWeight(.v) }
        set { setWeight(.v, newValue) }
    }

    /// The node's parent and its index there, if the parent is a tiling container. nil for the root container (its parent
    /// is a workspace), for the windows outside the tiling tree and for unbound nodes
    var tilingSlot: (parent: TilingContainer, index: Int)? {
        guard let parent = parent as? TilingContainer else { return nil }
        return (parent, parent.children.firstIndex(of: self).orDie())
    }

    /// The node and its ancestors, innermost first, each with its tiling parent and its index there. It ends below the root
    /// container, whose parent is a workspace. Empty for the root and for the windows outside the tiling tree
    var tilingPath: [(node: TreeNode, parent: TilingContainer, index: Int)] {
        var result: [(node: TreeNode, parent: TilingContainer, index: Int)] = []
        var node = self
        while let (parent, index) = node.tilingSlot {
            result.append((node, parent, index))
            node = parent
        }
        return result
    }

    /// The innermost tiling container along `direction` (and with `layout`, if not nil) in which the node, or the ancestor
    /// that the node is in, has a sibling in `direction`. Returns the container and the index of that node or ancestor
    func closestParent(hasChildrenIn direction: CardinalDirection, layout: Layout? = nil) -> (parent: TilingContainer, index: Int)? {
        tilingPath
            .first { (_, parent, index) in
                parent.orientation == direction.orientation && (layout == nil || parent.layout == layout) &&
                    parent.children.indices.contains(index + direction.focusOffset)
            }
            .map { ($0.parent, $0.index) }
    }

    /// The sibling in `direction` of the node, or of the innermost ancestor that has a sibling there. See
    /// ``closestParent(hasChildrenIn:layout:)``
    func neighbor(_ direction: CardinalDirection) -> TreeNode? {
        closestParent(hasChildrenIn: direction).map { $0.parent.children[$0.index + direction.focusOffset] }
    }

    /// The window of the subtree that is the closest to the `direction` side: along a container's orientation the child at
    /// that end, across it the most recent child. For a workspace, the window of its root container, which isn't created.
    /// E.g. focus enters a neighbor from the side opposite to the direction of the move: `neighbor.edgeWindow(snappedTo:
    /// direction.opposite)`. nil if a container on the way has no children
    func edgeWindow(snappedTo direction: CardinalDirection) -> Window? {
        switch self {
            case let window as Window: window
            case let workspace as Workspace: workspace.existingRootTilingContainer?.edgeWindow(snappedTo: direction)
            case let container as TilingContainer:
                (container.orientation == direction.orientation
                    ? (direction.isPositive ? container.children.last : container.children.first)
                    : container.mostRecentChild)?
                    .edgeWindow(snappedTo: direction)
            default: dieT("\(prettyDescription) isn't part of a tiling tree")
        }
    }
}

extension TilingContainer {
    /// The window whose last layout rect contains `point`. The virtual rects (as if the inner gaps were zero) cover the
    /// container without gaps, the physical ones are the windows' frames. An accordion's most recent child covers all of it
    func window(at point: CGPoint, virtual: Bool) -> Window? {
        let child: TreeNode? = switch layout {
            case .tiles:
                children.first { (virtual ? $0.lastAppliedLayoutVirtualRect : $0.lastAppliedLayoutPhysicalRect)?.contains(point) == true }
            case .accordion:
                mostRecentChild
        }
        guard let child else { return nil }
        return switch child {
            case let window as Window: window
            case let container as TilingContainer: container.window(at: point, virtual: virtual)
            default: dieT("\(child.prettyDescription) can't be a child of a tiling container")
        }
    }
}
