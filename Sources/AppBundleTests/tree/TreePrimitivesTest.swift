@testable import AppBundle
import AppKit
import Common
import Testing

/// The tree primitives that commands use. The trees are in workspace 'a', which isn't focused: there the last child of a
/// container is its most recent child, see ``setUpTree``
@Suite(.aeroSpaceGlobalState)
struct TreePrimitivesTest {
    @Test
    func tilingSlotAndPath() {
        let workspace = setUpTree("h_tiles(1 v_tiles(2 h_accordion(3))) floating(4)", workspace: "a")
        let root = workspace.rootTilingContainer
        #expect(testWindow(1).tilingSlot.map { "\(describeNode($0.parent)) \($0.index)" } == "h_tiles(1 v_tiles(2 h_accordion(3))) 0")
        #expect(testWindow(3).tilingPath.map { "\(describeNode($0.node)) in \($0.parent.orientation)_\($0.parent.layout) at \($0.index)" } == [
            "3 in h_accordion at 0",
            "h_accordion(3) in v_tiles at 1",
            "v_tiles(2 h_accordion(3)) in h_tiles at 1",
        ])
        // The root's parent is the workspace, a floating window's is the floating container
        #expect(root.tilingSlot == nil && root.tilingPath.isEmpty)
        #expect(testWindow(4).tilingSlot == nil && testWindow(4).tilingPath.isEmpty)
    }

    struct NeighborCase: Sendable, CustomTestStringConvertible {
        let tree: String
        let direction: CardinalDirection
        /// The neighbor of the focused window in the tree DSL
        let neighbor: String?
        var testDescription: String { "\(tree) \(direction)" }
    }

    @Test(arguments: [
        NeighborCase(tree: "h_tiles(1 *2 3)", direction: .left, neighbor: "1"),
        NeighborCase(tree: "h_tiles(1 *2 3)", direction: .right, neighbor: "3"),
        NeighborCase(tree: "h_tiles(1 *2 3)", direction: .up, neighbor: nil), // Across the orientation
        NeighborCase(tree: "h_tiles(*1 2)", direction: .left, neighbor: nil), // At the edge
        // Out of the containers that have no sibling in the direction
        NeighborCase(tree: "h_tiles(1 v_tiles(2 h_tiles(*3 4)))", direction: .left, neighbor: "1"),
        NeighborCase(tree: "h_tiles(1 v_tiles(2 h_tiles(*3 4)))", direction: .up, neighbor: "2"),
        NeighborCase(tree: "h_tiles(1 v_tiles(2 h_tiles(*3 4)))", direction: .right, neighbor: "4"),
        NeighborCase(tree: "h_tiles(1 v_tiles(2 h_tiles(*3 4)))", direction: .down, neighbor: nil),
        // A neighbor can be a container
        NeighborCase(tree: "h_tiles(*1 v_tiles(2 3))", direction: .right, neighbor: "v_tiles(2 3)"),
        // Floating windows aren't part of the tiling tree
        NeighborCase(tree: "h_tiles(1 2) floating(*3)", direction: .left, neighbor: nil),
    ])
    func neighbor(_ it: NeighborCase) {
        setUpTree(it.tree)
        let window = focus.windowOrNil.orDie()
        #expect(window.neighbor(it.direction).map { describeNode($0) } == it.neighbor)
        let closest = window.closestParent(hasChildrenIn: it.direction)
        #expect(closest.map { describeNode($0.parent.children[$0.index + it.direction.focusOffset]) } == it.neighbor)
    }

    @Test
    func closestParentWithLayout() {
        setUpTree("h_tiles(1 h_accordion(2 *3))")
        let window = testWindow(3)
        #expect(window.closestParent(hasChildrenIn: .left).map { "\($0.parent.layout) \($0.index)" } == "accordion 1")
        // The accordion is skipped: it's the root's child that has a sibling to the left
        #expect(window.closestParent(hasChildrenIn: .left, layout: .tiles).map { "\($0.parent.layout) \($0.index)" } == "tiles 1")
    }

    @Test
    func edgeWindow() {
        let workspace = setUpTree("h_tiles(1 v_tiles(2 3) 4)", workspace: "a")
        let root = workspace.rootTilingContainer
        let nested = testWindow(2).parent.orDie()
        // Along the orientation, the child at that end
        #expect(root.edgeWindow(snappedTo: .left)?.windowId == 1)
        #expect(root.edgeWindow(snappedTo: .right)?.windowId == 4)
        #expect(nested.edgeWindow(snappedTo: .up)?.windowId == 2)
        #expect(nested.edgeWindow(snappedTo: .down)?.windowId == 3)
        // Across the orientation, the most recent child
        #expect(root.edgeWindow(snappedTo: .up)?.windowId == 4)
        #expect(nested.edgeWindow(snappedTo: .left)?.windowId == 3)
        testWindow(2).markAsMostRecentChild()
        #expect(nested.edgeWindow(snappedTo: .right)?.windowId == 2)
        #expect(root.edgeWindow(snappedTo: .down)?.windowId == 3) // Across the root to the container, along it to the end
        #expect(workspace.edgeWindow(snappedTo: .left)?.windowId == 1) // A workspace's is its root's
        #expect(testWindow(4).edgeWindow(snappedTo: .left)?.windowId == 4)
    }

    @Test
    func edgeWindowOfAnEmptyWorkspace() {
        let workspace = Workspace.get(byName: "a")
        #expect(workspace.edgeWindow(snappedTo: .left) == nil)
        #expect(workspace.existingRootTilingContainer == nil) // Reading doesn't create the root
        #expect(setUpTree("h_tiles(v_tiles())", workspace: "b").edgeWindow(snappedTo: .left) == nil)
    }

    @Test
    func windowAtPoint() {
        world.config.gaps = Gaps(inner: .init(vertical: 20, horizontal: 20), outer: .init(left: 0, bottom: 0, top: 0, right: 0))
        let workspace = setUpTree("h_tiles(1 v_accordion(2 3))", workspace: "a")
        _ = workspace.layoutTiling() // Writes the rects: 1 is (0, 0, 950, 1079), its virtual rect is (0, 0, 960, 1080)
        let root = workspace.rootTilingContainer
        #expect(root.window(at: CGPoint(x: 100, y: 100), virtual: false)?.windowId == 1)
        // In the gap between the windows: only the virtual rects cover it
        #expect(root.window(at: CGPoint(x: 955, y: 100), virtual: false) == nil)
        #expect(root.window(at: CGPoint(x: 955, y: 100), virtual: true)?.windowId == 1)
        // An accordion's most recent child covers it
        #expect(root.window(at: CGPoint(x: 1500, y: 100), virtual: false)?.windowId == 3)
        testWindow(2).markAsMostRecentChild()
        #expect(root.window(at: CGPoint(x: 1500, y: 100), virtual: false)?.windowId == 2)
        #expect(root.window(at: CGPoint(x: 3000, y: 100), virtual: true) == nil) // Outside the monitor
    }

    @Test
    func moveWeightPolicies() {
        let workspace = setUpTree("h_tiles(1:2 2:4 v_tiles(3:5 4))", workspace: "a")
        let root = workspace.rootTilingContainer
        testWindow(1).move(to: root, at: 1, weight: .keep) // Within the parent: the index counts the children without the node
        #expect(describeTree("a", weights: true) == "h_tiles(2:4 1:2 v_tiles:1(3:5 4:1))")
        testWindow(4).move(to: root, at: 0) // .auto: the average weight of the new siblings
        #expect(describeTree("a", weights: true) == "h_tiles(4:2.3333333333333335 2:4 1:2 v_tiles:1(3:5))")
        testWindow(3).move(to: root, weight: .value(7)) // At the end
        #expect(describeTree("a", weights: true) == "h_tiles(4:2.3333333333333335 2:4 1:2 v_tiles:1() 3:7)")
        #expect(workspace.mostRecentWindowRecursive?.windowId == 3) // A moved node becomes the most recent one
        let binding = testWindow(2).move(to: workspace.floatingWindowsContainer)
        #expect(binding.map { "\($0.parent === root) \($0.index) \($0.weight)" } == "true 1 4.0")
        testWindow(4).move(to: binding.orDie()) // To where another node was: its parent, index and weight
        #expect(describeTree("a", weights: true) == "h_tiles(1:2 4:4 v_tiles:1() 3:7) floating(2)")
    }

    @Test
    func wrap() {
        let workspace = setUpTree("h_tiles(1 2:3 3)", workspace: "a")
        let container = testWindow(2).wrap(.v, .accordion)
        #expect(describeTree("a", weights: true) == "h_tiles(1:1 v_accordion:3(2:1) 3:1)")
        #expect(workspace.mostRecentWindowRecursive?.windowId == 2) // The node is the most recent child of the new container
        #expect(container.wrap(.h, .tiles).children.singleOrNil() === container)
        #expect(describeTree("a") == "h_tiles(1 h_tiles(v_accordion(2)) 3)")
    }

    @Test
    func wrapTheRoot() {
        let workspace = setUpTree("floating(3) h_tiles(1 2)", workspace: "a")
        let root = workspace.rootTilingContainer
        let newRoot = root.wrap(.v, .tiles)
        #expect(workspace.rootTilingContainer === newRoot)
        #expect(describeTree("a", weights: true) == "v_tiles(h_tiles:1(1:1 2:1)) floating(3)")
        #expect(describeNode(workspace) == "floating(3) v_tiles(h_tiles(1 2))") // The new root takes the old one's place
    }

    @Test(arguments: [
        // Siblings, in both directions
        ("h_tiles(1:2 2 3:4)", 1 as UInt32, 3 as UInt32, "h_tiles(3:2 2:1 1:4)"),
        ("h_tiles(1:2 2 3:4)", 3, 1, "h_tiles(3:2 2:1 1:4)"),
        // Different parents
        ("h_tiles(1:2 v_tiles(2 3:4))", 1, 3, "h_tiles(3:2 v_tiles:1(2:1 1:4))"),
    ] as [(String, UInt32, UInt32, String)])
    func swap(tree: String, a: UInt32, b: UInt32, after: String) {
        let workspace = setUpTree(tree, workspace: "a")
        testWindow(a).swap(with: testWindow(b))
        #expect(describeTree("a", weights: true) == after)
        #expect(workspace.mostRecentWindowRecursive?.windowId == a) // The receiver ends up the more recent one
    }

    @Test
    func temporaryEditsAreUndone() {
        let workspace = setUpTree("h_tiles(1:2 v_tiles(2 3) 4) floating(5 6)", workspace: "a")
        testWindow(2).markAsMostRecentChild()
        let before = (describeNode(workspace), describeTree("a", weights: true), describeNode(workspace, mru: true))
        #expect(before.2 == "h_tiles(v_tiles(2 3) 4 1) floating(6 5)")
        let root = workspace.rootTilingContainer
        let result = workspace.withTemporaryEdits {
            testWindow(6).move(to: root, at: 0, weight: .value(1))
            testWindow(5).move(to: testWindow(3).parent.orDie(), at: 2, weight: .value(1))
            testWindow(4).wrap(.v, .accordion)
            testWindow(1).swap(with: testWindow(3))
            testWindow(4).markAsMostRecentChild()
            return describeTree("a")
        }
        #expect(result == "h_tiles(6 3 v_tiles(2 1 5) v_accordion(4))")
        #expect((describeNode(workspace), describeTree("a", weights: true), describeNode(workspace, mru: true)) == before)
        #expect(testWindow(5).parent === workspace.floatingWindowsContainer)
        #expect(workspace.mostRecentWindowRecursive?.windowId == 2)
    }

    @Test
    func temporaryEditsCanCreateTheRoot() {
        let workspace = setUpTree("floating(1)", workspace: "a")
        workspace.withTemporaryEdits {
            testWindow(1).move(to: workspace.rootTilingContainer)
            #expect(workspace.existingRootTilingContainer != nil)
        }
        #expect(workspace.existingRootTilingContainer == nil)
        #expect(describeTree("a") == "h_tiles() floating(1)")
        #expect(workspace.mostRecentWindowRecursive?.windowId == 1)
    }

    @Test
    func readingDoesntCreateTheRoot() {
        let workspace = setUpTree("floating(1)", workspace: "a")
        #expect(workspace.tilingWindows.isEmpty)
        #expect(workspace.rootLayout.layout == .tiles && workspace.rootLayout.orientation == .h) // The config's default
        #expect(workspace.existingRootTilingContainer == nil)
        workspace.rootTilingContainer.layout = .accordion
        #expect(workspace.rootLayout.layout == .accordion)
        #expect(setUpTree("h_tiles(1 v_tiles(2 3))", workspace: "b").tilingWindows.map(\.windowId) == [1, 2, 3])
    }
}
