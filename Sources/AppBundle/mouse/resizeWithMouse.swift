import AppKit
import Common

func resetManipulatedWithMouseIfPossible() async throws {
    if world.mouseManipulatedWindowId != nil {
        world.mouseManipulatedWindowId = nil
        for workspace in Workspace.all {
            workspace.resetResizeWeightBeforeResizeRecursive()
        }
        world.sessions.scheduleHeavy(.resetManipulatedWithMouse, preLayout: true)
    }
}

func resizeWithMouse(_ window: Window) async throws { // todo cover with tests
    resetClosedWindowsCache()
    guard case .tiling(let parent) = window.placement else { return } // Nothing to do for floating, or unconventional windows
    guard let rect = try await window.getAxRect(.cancellable) else { return }
    if window.parent !== parent { return } // The window closed or moved at the suspension point above
    guard let lastAppliedLayoutRect = window.lastAppliedLayoutPhysicalRect else { return }
    let (lParent, lOwnIndex) = window.closestParent(hasChildrenIn: .left, layout: .tiles) ?? (nil, nil)
    let (dParent, dOwnIndex) = window.closestParent(hasChildrenIn: .down, layout: .tiles) ?? (nil, nil)
    let (uParent, uOwnIndex) = window.closestParent(hasChildrenIn: .up, layout: .tiles) ?? (nil, nil)
    let (rParent, rOwnIndex) = window.closestParent(hasChildrenIn: .right, layout: .tiles) ?? (nil, nil)
    let table: [(CGFloat, TilingContainer?, Int?, Int?)] = [
        (lastAppliedLayoutRect.minX - rect.minX, lParent, 0,                        lOwnIndex),               // Horizontal, to the left of the window
        (rect.maxY - lastAppliedLayoutRect.maxY, dParent, dOwnIndex.map { $0 + 1 }, dParent?.children.count), // Vertical, to the down of the window
        (lastAppliedLayoutRect.minY - rect.minY, uParent, 0,                        uOwnIndex),               // Vertical, to the up of the window
        (rect.maxX - lastAppliedLayoutRect.maxX, rParent, rOwnIndex.map { $0 + 1 }, rParent?.children.count), // Horizontal, to the right of the window
    ]
    for (diff, parent, startIndex, pastTheEndIndex) in table {
        if let parent, let startIndex, let pastTheEndIndex, pastTheEndIndex - startIndex > 0 && abs(diff) > 5 { // 5 pixels should be enough to fight with accumulated floating precision error
            let siblingDiff = diff.div(pastTheEndIndex - startIndex).orDie()
            let orientation = parent.orientation

            for step in window.tilingPath {
                if step.node == parent { break }
                if step.parent.orientation == orientation && step.parent.layout == .tiles {
                    step.node.setWeight(orientation, step.node.getWeightBeforeResize(orientation) + diff)
                }
            }
            for sibling in parent.children[startIndex ..< pastTheEndIndex] {
                sibling.setWeight(orientation, sibling.getWeightBeforeResize(orientation) - siblingDiff)
            }
        }
    }
    world.mouseManipulatedWindowId = window.windowId
}

extension TreeNode {
    fileprivate func getWeightBeforeResize(_ orientation: Orientation) -> CGFloat {
        let currentWeight = getWeight(orientation) // Check assertions
        if let weightBeforeResizeWithMouse { return weightBeforeResizeWithMouse }
        let weight = lastAppliedLayoutVirtualRect?.getDimension(orientation) ?? currentWeight
        weightBeforeResizeWithMouse = weight
        return weight
    }

    fileprivate func resetResizeWeightBeforeResizeRecursive() {
        weightBeforeResizeWithMouse = nil
        for child in children {
            child.resetResizeWeightBeforeResizeRecursive()
        }
    }
}
