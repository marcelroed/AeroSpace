@testable import AppBundle
import AppKit

extension TilingContainer {
    static func newHTiles(parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat) -> TilingContainer {
        TilingContainer(parent: parent, adaptiveWeight: adaptiveWeight, .h, .tiles, index: INDEX_BIND_LAST)
    }

    static func newVTiles(parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat) -> TilingContainer {
        TilingContainer(parent: parent, adaptiveWeight: adaptiveWeight, .v, .tiles, index: INDEX_BIND_LAST)
    }
}
