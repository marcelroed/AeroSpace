@testable import AppBundle
import AppKit

extension TilingContainer {
    /// todo: superseded by the tree DSL (treeDsl.swift). Delete it once ListWindowsTest is converted
    static func newVTiles(parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat) -> TilingContainer {
        TilingContainer(parent: parent, adaptiveWeight: adaptiveWeight, .v, .tiles, index: INDEX_BIND_LAST)
    }
}
