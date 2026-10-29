import AppKit
import Common

/// The kinds of containers. The legal edges of the tree are in ``TreeNode/canBeChild(of:)``
enum ContainerKind: Equatable {
    /// ``TilingContainer``: lays out windows and tiling containers. A workspace has one, its root
    case tiling
    /// A workspace's windows outside of its tiling tree: floating, macOS native fullscreen, windows of hidden apps.
    /// A workspace has at most one of each kind
    case floating, macosFullscreen, macosHiddenApp
    /// The global container of minimized windows. It's a root: it isn't part of any workspace
    case macosMinimized
    /// The global container of the objects that are windows from the AX perspective, but not even dialogs from the human
    /// perspective. E.g. Sonoma (macOS 14) keyboard layout switch. It's a root, like ``macosMinimized``
    case macosPopup
}

/// A node with children that isn't a workspace. ``TilingContainer`` is the tiling kind; the other kinds hold only windows
class Container: TreeNode {
    let kind: ContainerKind

    /// A workspace's floating, macOS fullscreen or hidden-app container
    init(_ kind: ContainerKind, parent: Workspace) {
        self.kind = kind
        super.init(parent: parent)
    }

    /// The global containers of minimized and popup windows: see ``World``
    init(root kind: ContainerKind) {
        self.kind = kind
        super.init()
    }

    fileprivate init(tilingParent parent: TreeNode, weight: CGFloat?, index: Int?) {
        self.kind = .tiling
        super.init(parent: parent, weight: weight, index: index)
    }
}

final class TilingContainer: Container {
    fileprivate(set) var orientation: Orientation
    var layout: Layout

    /// `parent` is a workspace (the root container) or a tiling container. See ``TreeNode/move(to:at:weight:)`` for
    /// `weight` and `index`
    init(parent: TreeNode, weight: CGFloat? = nil, _ orientation: Orientation, _ layout: Layout, index: Int? = nil) {
        self.orientation = orientation
        self.layout = layout
        super.init(tilingParent: parent, weight: weight, index: index)
    }
}

extension TilingContainer {
    var isRootContainer: Bool { parent is Workspace }

    /// Setting it doesn't normalize the nested containers, unlike ``changeOrientation(_:)``: it puts back a saved state,
    /// see ``World/withTemporaryTreeEdits(_:)``
    var orientationAndLayout: (Orientation, Layout) {
        get { (orientation, layout) }
        set { (orientation, layout) = newValue }
    }

    func changeOrientation(_ targetOrientation: Orientation) {
        if orientation == targetOrientation {
            return
        }
        if config.enableNormalizationOppositeOrientationForNestedContainers {
            var orientation = targetOrientation
            for container in [self] + tilingPath.map(\.parent) {
                container.orientation = orientation
                orientation = orientation.opposite
            }
        } else {
            self.orientation = targetOrientation
        }
    }

    func normalizeOppositeOrientationForNestedContainers() {
        if orientation == (parent as? TilingContainer)?.orientation {
            orientation = orientation.opposite
        }
        for child in children {
            (child as? TilingContainer)?.normalizeOppositeOrientationForNestedContainers()
        }
    }
}

enum Layout: String {
    case tiles
    case accordion
}
