@testable import AppBundle
import AppKit

extension TilingContainer {
    /// todo: superseded by the tree DSL (treeDsl.swift). Delete it once ListWindowsTest is converted
    static func newVTiles(parent: NonLeafTreeNodeObject, weight: CGFloat) -> TilingContainer {
        TilingContainer(parent: parent, weight: weight, .v, .tiles)
    }
}
