import AppKit
import Common

final class TilingContainer: TreeNode, NonLeafTreeNodeObject { // todo consider renaming to GenericContainer
    fileprivate(set) var orientation: Orientation
    var layout: Layout

    init(parent: NonLeafTreeNodeObject, weight: CGFloat? = nil, _ orientation: Orientation, _ layout: Layout, index: Int? = nil) {
        self.orientation = orientation
        self.layout = layout
        super.init(parent: parent, weight: weight, index: index)
    }
}

extension TilingContainer {
    var isRootContainer: Bool { parent is Workspace }

    func changeOrientation(_ targetOrientation: Orientation) {
        if orientation == targetOrientation {
            return
        }
        if config.enableNormalizationOppositeOrientationForNestedContainers {
            var orientation = targetOrientation
            parentsWithSelf
                .filterIsInstance(of: TilingContainer.self)
                .forEach {
                    $0.orientation = orientation
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

extension String {
    func parseLayout() -> Layout? {
        switch Layout(rawValue: self) {
            case let parsed?: parsed
            case nil where self == "list": .tiles
            case nil: nil
        }
    }
}
