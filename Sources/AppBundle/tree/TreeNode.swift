import AppKit
import Common

/// The tree is main actor state. Subclasses and extensions inherit the isolation (async members too),
/// so a member that must not be isolated has to be marked `nonisolated`
open class TreeNode: Equatable, AeroAny {
    private(set) final var children: [TreeNode] = []
    fileprivate(set) final weak var parent: NonLeafTreeNodeObject? = nil
    private var adaptiveWeight: CGFloat
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
    private var unboundStacktrace: String? = nil
    var isBound: Bool { parent != nil } // todo drop, once https://github.com/nikitabobko/AeroSpace/issues/1215 is fixed

    init(parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat, index: Int) {
        self.adaptiveWeight = adaptiveWeight
        bind(to: parent, adaptiveWeight: adaptiveWeight, index: index)
    }

    /// Creates a node that is never bound to a parent (Workspace and the global macOS unconventional windows containers)
    init(unboundRootWithAdaptiveWeight adaptiveWeight: CGFloat) {
        self.adaptiveWeight = adaptiveWeight
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
                adaptiveWeight = newValue
            default:
                die("Can't change weight")
        }
    }

    /// Weight itself doesn't make sense. The parent container controls semantics of weight
    func getWeight(_ targetOrientation: Orientation) -> CGFloat {
        guard let parent else { die("Weight doesn't make sense for containers without parent") }
        return switch getChildParentRelation(child: self, parent: parent) {
            case .tiling(let parent):
                parent.orientation == targetOrientation ? adaptiveWeight : parent.getWeight(targetOrientation)
            case .rootTilingContainer: parent.getWeight(targetOrientation)
            case .floatingWindow, .macosNativeFullscreenWindow: dieT("Weight doesn't make sense for floating windows")
            case .macosNativeMinimizedWindow: dieT("Weight doesn't make sense for minimized windows")
            case .macosPopupWindow: dieT("Weight doesn't make sense for popup windows")
            case .macosNativeHiddenAppWindow: dieT("Weight doesn't make sense for windows of hidden apps")
            case .shimContainerRelation: dieT("Weight doesn't make sense for stub containers")
        }
    }

    @discardableResult
    func bind(to newParent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat, index: Int) -> BindingData? {
        // bind() overwrites unboundStacktrace below, so don't spend time on recording it
        let result = unbindIfBound(recordStacktrace: false)

        let relation = getChildParentRelation(child: self, parent: newParent) // Side effect: verify relation
        if adaptiveWeight == WEIGHT_AUTO {
            self.adaptiveWeight = switch relation {
                case .tiling(let newParent):
                    newParent.children.sum { $0.getWeight(newParent.orientation) }.div(newParent.children.count) ?? 1
                case .floatingWindow, .macosNativeFullscreenWindow, .rootTilingContainer, .macosNativeMinimizedWindow,
                     .shimContainerRelation, .macosPopupWindow, .macosNativeHiddenAppWindow:
                    WEIGHT_DOESNT_MATTER
            }
        } else {
            self.adaptiveWeight = adaptiveWeight
        }
        newParent.children.insert(self, at: index != INDEX_BIND_LAST ? index : newParent.children.count)
        parent = newParent
        unboundStacktrace = nil
        // todo consider disabling automatic mru propogation
        // 1. "floating windows" in FocusCommand break the MRU because of that :(
        // 2. Misbehaved apps that abuse real window as popups https://github.com/nikitabobko/AeroSpace/issues/106 (the
        //    last appeared window, is not necessarily the one that has the focus)
        markAsMostRecentChild()
        return result
    }

    private func unbindIfBound(recordStacktrace: Bool) -> BindingData? {
        guard let parent else { return nil }

        let index = parent.children.firstIndex(of: self) ?? dieT("Can't find child in its parent")
        parent.children.remove(at: index)
        self.parent = nil
        if recordStacktrace {
            unboundStacktrace = getStringStacktrace()
        }

        return BindingData(parent: parent, adaptiveWeight: adaptiveWeight, index: index)
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

    @discardableResult
    func unbindFromParent() -> BindingData {
        unbindIfBound(recordStacktrace: true) ?? dieT("\(prettyDescription) is already unbound. The stacktrace where it was unbound:\n\(unboundStacktrace.prettyDescription)")
    }

    nonisolated public static func == (lhs: TreeNode, rhs: TreeNode) -> Bool {
        lhs === rhs
    }
}

@MainActor private var mruClock: UInt64 = 0

let WEIGHT_DOESNT_MATTER = CGFloat(-2)
/// Splits containers evenly if tiling.
///
/// Reset weight is bind to workspace (aka "floating windows")
let WEIGHT_AUTO = CGFloat(-1)

let INDEX_BIND_LAST = -1

struct BindingData {
    let parent: NonLeafTreeNodeObject
    let adaptiveWeight: CGFloat
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
