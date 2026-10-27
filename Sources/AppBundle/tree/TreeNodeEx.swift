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

    var ownIndex: Int? {
        guard let parent else { return nil }
        return parent.children.firstIndex(of: self).orDie()
    }

    /// From the closest parent to the root
    var parents: [TreeNode] {
        var result: [TreeNode] = []
        var current = parent
        while let node = current {
            result.append(node)
            current = node.parent
        }
        return result
    }

    /// `self` followed by ``parents``
    var parentsWithSelf: [TreeNode] {
        var result: [TreeNode] = [self]
        var current = parent
        while let node = current {
            result.append(node)
            current = node.parent
        }
        return result
    }

    var nodeWorkspace: Workspace? {
        self as? Workspace ?? parent?.nodeWorkspace
    }

    /// nil for the minimized and popup windows: their containers are roots, like workspaces
    var nodeMonitor: MonitorInfo? { nodeWorkspace?.workspaceMonitor }

    /// Follows the most recent children down to a window. A child without windows (an empty root container) is skipped
    /// for the next most recent one
    var mostRecentWindowRecursive: Window? {
        if let window = self as? Window { return window }
        return mostRecentChild?.mostRecentWindowRecursive ?? mruChildren.dropFirst().lazy.compactMap(\.mostRecentWindowRecursive).first
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

    /// Returns closest parent that has children in the specified direction relative to `self`
    func closestParent(
        hasChildrenInDirection direction: CardinalDirection,
        withLayout layout: Layout?,
    ) -> (parent: TilingContainer, ownIndex: Int)? {
        let innermostChild = parentsWithSelf.first(where: { node in
            // stop searching if the parent isn't a tiling container. We didn't find it, or something went wrong
            guard let parent = node.parent as? TilingContainer else { return true }
            return (layout == nil || parent.layout == layout) &&
                parent.orientation == direction.orientation &&
                (node.ownIndex.map { parent.children.indices.contains($0 + direction.focusOffset) } ?? true)
        })
        guard let innermostChild, let parent = innermostChild.parent as? TilingContainer else { return nil }
        check(parent.orientation == direction.orientation)
        return innermostChild.ownIndex.map { (parent, $0) }
    }
}
