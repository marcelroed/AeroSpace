import AppKit
import Common

/// The tree is main actor state. Subclasses and extensions inherit the isolation (async members too),
/// so a member that must not be isolated has to be marked `nonisolated`
open class TreeNode: Equatable, AeroAny {
    private(set) final var children: [TreeNode] = []
    fileprivate(set) final weak var parent: NonLeafTreeNodeObject? = nil
    private var weight: CGFloat
    /// The most recent child of a node is the child with the highest stamp. See ``markAsMostRecentChild()``
    private var mruStamp: UInt64 = 0
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

    /// See ``bind(to:weight:index:)`` for `weight` and `index`
    init(parent: NonLeafTreeNodeObject, weight: CGFloat? = nil, index: Int? = nil) {
        self.weight = 0 // bind() sets it
        bind(to: parent, weight: weight, index: index)
    }

    /// Creates a node that is never bound to a parent (Workspace and the global macOS unconventional windows containers)
    init() {
        weight = weightDoesntMatter
    }

    /// See: ``getWeight(_:)``
    func setWeight(_ targetOrientation: Orientation, _ newValue: CGFloat) {
        guard let parent else { die("Can't change weight if TreeNode doesn't have parent") }
        switch getChildParentRelation(child: self, parent: parent) {
            case .tiling(let parent):
                if parent.orientation != targetOrientation {
                    die("You can't change \(targetOrientation) weight of nodes located in \(parent.orientation) container")
                }
                if parent.layout != .tiles {
                    die("Weight can be changed only for nodes whose parent has 'tiles' layout")
                }
                weight = newValue
            default:
                die("Can't change weight")
        }
    }

    /// Weight itself doesn't make sense. The parent container controls semantics of weight
    func getWeight(_ targetOrientation: Orientation) -> CGFloat {
        guard let parent else { die("Weight doesn't make sense for containers without parent") }
        return switch getChildParentRelation(child: self, parent: parent) {
            case .tiling(let parent):
                parent.orientation == targetOrientation ? weight : parent.getWeight(targetOrientation)
            case .rootTilingContainer: parent.getWeight(targetOrientation)
            case .floatingWindow, .macosNativeFullscreenWindow: dieT("Weight doesn't make sense for floating windows")
            case .macosNativeMinimizedWindow: dieT("Weight doesn't make sense for minimized windows")
            case .macosPopupWindow: dieT("Weight doesn't make sense for popup windows")
            case .macosNativeHiddenAppWindow: dieT("Weight doesn't make sense for windows of hidden apps")
            case .shimContainerRelation: dieT("Weight doesn't make sense for stub containers")
        }
    }

    /// Inserts the node at `index` of `newParent`'s children (nil: last), and makes it the most recent child.
    /// `weight` nil: the average weight of the new siblings in a tiling container (1 without siblings), and
    /// ``weightDoesntMatter`` in any other container. Returns where the node was bound before
    @discardableResult
    func bind(to newParent: NonLeafTreeNodeObject, weight: CGFloat? = nil, index: Int? = nil) -> NodeBinding? {
        let result = parent != nil ? unbindFromParent() : nil

        let relation = getChildParentRelation(child: self, parent: newParent) // Side effect: verify relation
        self.weight = if let weight { weight } else {
            switch relation {
                case .tiling(let newParent):
                    newParent.children.sum { $0.getWeight(newParent.orientation) }.div(newParent.children.count) ?? 1
                case .floatingWindow, .macosNativeFullscreenWindow, .rootTilingContainer, .macosNativeMinimizedWindow,
                     .shimContainerRelation, .macosPopupWindow, .macosNativeHiddenAppWindow:
                    weightDoesntMatter
            }
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
        mruClock += 1
        var node: TreeNode? = self
        while let current = node {
            current.mruStamp = mruClock
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

@MainActor private var mruClock: UInt64 = 0

/// The weight of a node whose parent isn't a tiling container. It's observable: commands that keep a node's weight
/// (e.g. swap, focus --floating-as-tiling) carry it into tiling containers
private let weightDoesntMatter = CGFloat(-2)

/// Where a node is bound: ``TreeNode/bind(to:weight:index:)`` with these values puts it back
struct NodeBinding {
    let parent: NonLeafTreeNodeObject
    let weight: CGFloat
    let index: Int
}

extension TreeNode {
    /// For crash messages. TreeNode isn't CustomStringConvertible, so "\(node)" prints only the type name
    var prettyDescription: String {
        switch self {
            case let window as Window: "Window(id: \(window.windowId), workspace: \(window.nodeWorkspace?.name.singleQuoted ?? "nil"))"
            case let workspace as Workspace: "Workspace(\(workspace.name.singleQuoted))"
            default: "\(type(of: self))(workspace: \(nodeWorkspace?.name.singleQuoted ?? "nil"))"
        }
    }
}
