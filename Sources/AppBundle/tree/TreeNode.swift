import AppKit
import Common

/// The tree is main actor state. Subclasses and extensions inherit the isolation (async members too),
/// so a member that must not be isolated has to be marked `nonisolated`
open class TreeNode: Equatable {
    fileprivate(set) final var children: [TreeNode] = []
    fileprivate(set) final weak var parent: TreeNode? = nil
    fileprivate var weight: CGFloat
    /// The most recent child of a node is the child with the highest stamp. See ``markAsMostRecentChild()``
    fileprivate var mruStamp: UInt64 = 0
    // Usages:
    // - resize with mouse
    // - makeFloatingWindowsSeenAsTiling in focus command
    var lastAppliedLayoutVirtualRect: Rect? = nil  // as if inner gaps were always zero
    // Usages:
    // - resize with mouse
    // - drag window with mouse
    // - move-mouse command
    // - focus-follows-mouse
    var lastAppliedLayoutPhysicalRect: Rect? = nil // with real inner gaps
    // Usages:
    // - resize with mouse
    var weightBeforeResizeWithMouse: CGFloat? = nil
    var isBound: Bool { parent != nil } // todo drop, once https://github.com/nikitabobko/AeroSpace/issues/1215 is fixed

    /// See ``move(to:at:weight:)`` for `index`. `weight` nil: ``WeightPolicy/auto``
    init(parent: TreeNode, weight: CGFloat? = nil, index: Int? = nil) {
        self.weight = 0 // move() sets it
        move(to: parent, at: index, weight: weight.map { .value($0) } ?? .auto)
    }

    /// Creates a node that is never bound to a parent (Workspace and the global macOS unconventional windows containers)
    init() {
        weight = weightDoesntMatter
    }

    /// See: ``getWeight(_:)``
    func setWeight(_ targetOrientation: Orientation, _ newValue: CGFloat) {
        guard let parent = parent as? TilingContainer else { die("Only the children of tiling containers have weights") }
        if parent.orientation != targetOrientation {
            die("You can't change \(targetOrientation) weight of nodes located in \(parent.orientation) container")
        }
        if parent.layout != .tiles {
            die("Weight can be changed only for nodes whose parent has 'tiles' layout")
        }
        weight = newValue
    }

    /// Weight itself doesn't make sense. The parent container controls semantics of weight
    func getWeight(_ targetOrientation: Orientation) -> CGFloat {
        switch parent {
            case let parent as TilingContainer:
                parent.orientation == targetOrientation ? weight : parent.getWeight(targetOrientation)
            case let parent as Workspace where self is TilingContainer: parent.getWeight(targetOrientation) // The root
            default: dieT("Weight doesn't make sense for \(prettyDescription)")
        }
    }

    /// Moves the node to `index` of `newParent`'s children (nil: last), and makes it the most recent child. The index counts
    /// the children without the node, so a node can move within its parent. Returns where the node was before, nil if it was
    /// unbound
    @discardableResult
    func move(to newParent: TreeNode, at index: Int? = nil, weight: WeightPolicy = .auto) -> NodeBinding? {
        let result = parent != nil ? unbindFromParent() : nil
        check(canBeChild(of: newParent), "\(prettyDescription) can't be a child of \(newParent.prettyDescription)")
        switch weight {
            case .keep: break
            case .auto:
                self.weight = (newParent as? TilingContainer).map { newParent in
                    newParent.children.sum { $0.getWeight(newParent.orientation) }.div(newParent.children.count) ?? 1
                } ?? weightDoesntMatter
            case .value(let value): self.weight = value
        }
        newParent.children.insert(self, at: index ?? newParent.children.count)
        parent = newParent
        // todo consider disabling automatic mru propogation
        // 1. "floating windows" in FocusCommand break the MRU because of that :(
        // 2. Misbehaved apps that abuse real window as popups https://github.com/nikitabobko/AeroSpace/issues/106 (the
        //    last appeared window, is not necessarily the one that has the focus)
        markAsMostRecentChild()
        return result
    }

    /// Moves the node to where another node was bound, with that node's weight: `node.move(to: other.unbindFromParent())`
    /// puts `node` in `other`'s place
    func move(to binding: NodeBinding) {
        move(to: binding.parent, at: binding.index, weight: .value(binding.weight))
    }

    /// Returns where the node was bound
    @discardableResult
    func unbindFromParent() -> NodeBinding {
        guard let parent else { die("\(prettyDescription) is already unbound") }
        let index = parent.children.firstIndex(of: self) ?? dieT("Can't find child in its parent")
        parent.children.remove(at: index)
        self.parent = nil
        return NodeBinding(parent: parent, weight: weight, index: index)
    }

    /// Makes the node the most recent child of its parent, and the parent the most recent child of its parent, and so on.
    /// Every bind does it, so every child has a stamp, and siblings never share one: one call gives one node per level
    /// the same new stamp
    func markAsMostRecentChild() {
        world.mruClock += 1
        let stamp = world.mruClock
        var node: TreeNode? = self
        while let current = node {
            current.mruStamp = stamp
            node = current.parent
        }
    }

    var mostRecentChild: TreeNode? { children.max { $0.mruStamp < $1.mruStamp } }

    /// The children, the most recent first
    var mruChildren: [TreeNode] { children.sorted { $0.mruStamp > $1.mruStamp } }

    nonisolated public static func == (lhs: TreeNode, rhs: TreeNode) -> Bool {
        lhs === rhs
    }
}

/// The weight of a node whose parent isn't a tiling container. It's observable: commands that keep a node's weight
/// (e.g. swap, focus --floating-as-tiling) carry it into tiling containers
private let weightDoesntMatter = CGFloat(-2)

/// How ``TreeNode/move(to:at:weight:)`` sets the weight of the moved node
enum WeightPolicy {
    /// The node keeps its weight, e.g. when it moves within its parent
    case keep
    /// In a tiling container, the average weight of the new siblings (1 without siblings). ``weightDoesntMatter`` in any
    /// other container
    case auto
    case value(CGFloat)
}

/// Where a node is bound: ``TreeNode/move(to:)`` puts a node there
struct NodeBinding {
    let parent: TreeNode
    let weight: CGFloat
    let index: Int
}

extension TreeNode {
    /// The legal edges of the tree. ``move(to:at:weight:)`` checks them, so code that walks the tree can rely on them
    func canBeChild(of parent: TreeNode) -> Bool {
        switch (self, parent) {
            case (is Window, is Container): true
            case (is TilingContainer, is TilingContainer), (is TilingContainer, is Workspace): true
            case (let container as Container, is Workspace): [.floating, .macosFullscreen, .macosHiddenApp].contains(container.kind)
            default: false
        }
    }

    /// For crash messages. TreeNode isn't CustomStringConvertible, so "\(node)" prints only the type name
    var prettyDescription: String {
        switch self {
            case let window as Window: "Window(id: \(window.windowId), workspace: \(window.nodeWorkspace?.name.singleQuoted ?? "nil"))"
            case let workspace as Workspace: "Workspace(\(workspace.name.singleQuoted))"
            case let container as Container: "Container(kind: \(container.kind), workspace: \(nodeWorkspace?.name.singleQuoted ?? "nil"))"
            default: "\(type(of: self))(workspace: \(nodeWorkspace?.name.singleQuoted ?? "nil"))"
        }
    }
}

extension TreeNode {
    /// Puts a new tiling container in the node's place (its parent, index and weight) and moves the node into it. Works for
    /// the root container too: the new container becomes the root. Returns the new container
    @discardableResult
    func wrap(_ orientation: Orientation, _ layout: Layout) -> TilingContainer {
        let binding = unbindFromParent()
        let container = TilingContainer(parent: binding.parent, weight: binding.weight, orientation, layout, index: binding.index)
        move(to: container)
        return container
    }

    /// The nodes trade places: parent, index and weight. `self` ends up the more recent one
    func swap(with other: TreeNode) {
        if self == other { return }
        let otherBinding = other.unbindFromParent()
        let binding = unbindFromParent()
        other.move(to: binding)
        move(to: otherBinding)
    }
}

extension Workspace {
    /// Runs `body`, then puts the workspace back exactly as it was: the children of every node, their order, their weights
    /// and the MRU order. For edits that only last for a computation, e.g. focus sees floating windows as tiling windows.
    /// `body` may move nodes within the workspace and create containers in it (they are dropped), but must not move windows
    /// in or out. A workspace has no parent, so the edits can't mark anything outside it as most recent
    func withTemporaryEdits<T, E: Error>(_ body: () throws(E) -> T) throws(E) -> T {
        var saved: [(node: TreeNode, children: [TreeNode], weight: CGFloat, mruStamp: UInt64)] = []
        func save(_ node: TreeNode) {
            saved.append((node, node.children, node.weight, node.mruStamp))
            node.children.forEach(save)
        }
        save(self)
        let windows = allLeafWindowsRecursive.toSet()
        defer {
            check(allLeafWindowsRecursive.toSet() == windows, "Temporary edits moved windows in or out of \(prettyDescription)")
            for (node, children, weight, mruStamp) in saved {
                node.children = children
                children.forEach { $0.parent = node }
                node.weight = weight
                node.mruStamp = mruStamp
            }
        }
        return try body()
    }
}
