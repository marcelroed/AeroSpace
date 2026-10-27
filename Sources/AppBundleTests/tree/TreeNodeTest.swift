@testable import AppBundle
import Testing

@Suite(.aeroSpaceGlobalState)
struct TreeNodeTest {
    @Test
    func childParentCyclicReferenceMemoryLeak() {
        let workspace = focus.workspace // Don't cache root node
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainerCreatingIfNeeded())

        #expect(window.parent != nil)
        workspace.existingRootTilingContainer?.unbindFromParent()
        expectEqual(window.parent, nil) // TreeNode.parent is weak: nil means that the unbound root was deallocated
    }

    @Test(arguments: [
        // Containers without windows are removed, but not the root
        (false, "h_tiles(v_tiles(h_tiles()))", "h_tiles()"),
        (false, "h_tiles()", "h_tiles()"),
        (true, "h_tiles()", "h_tiles()"),
        // A container with a single child is flattened only if enabled
        (false, "h_tiles(v_tiles(1))", "h_tiles(v_tiles(1))"),
        (true, "h_tiles(v_tiles(1))", "v_tiles(1)"), // The single child container replaces the root
        (true, "h_tiles(0 h_tiles(1))", "h_tiles(0 1)"),
    ] as [(Bool, String, String)])
    func normalizeContainers(flattenContainers: Bool, before: String, after: String) {
        world.config.enableNormalizationFlattenContainers = flattenContainers
        let workspace = setUpTree(before, workspace: "a")
        workspace.normalizeContainers()
        expectEqual(describeTree("a"), after)
        #expect(workspace.existingRootTilingContainer != nil) // describeTree prints the root that the workspace would get
    }

    /// RB-03: creating a container bound it as the most recent child, so toLiveFocus() fell back to the first window
    @Test(arguments: [.tiling, .floating, .macosFullscreen, .macosHiddenApp] as [ContainerKind])
    func creatingAContainerKeepsTheMostRecentWindow(kind: ContainerKind) {
        let workspace = setUpTree(kind == .tiling ? "floating(1 2)" : "h_tiles(1 2)", workspace: "a") // 2 was bound last
        _ = kind == .tiling ? workspace.rootTilingContainerCreatingIfNeeded() : workspace.containerCreatingIfNeeded(kind)
        expectEqual(workspace.toLiveFocus().windowOrNil?.windowId, 2)
    }

    @Test
    func aWeightInTheOtherOrientationIsTheParents() {
        setUpTree("h_tiles(1:2 v_tiles:3(4 5:0.5))")
        expectEqual(testWindow(5).vWeight, 0.5)
        expectEqual(testWindow(5).hWeight, 3)
    }

    @Test
    func focusingAWorkspaceFocusesItsMostRecentWindow() {
        let a = setUpTree("h_tiles(*1 v_tiles(2 3))", workspace: "a")
        let b = setUpTree("h_tiles(4 5)", workspace: "b") // 5 was bound last
        #expect(b.focusWorkspace())
        expectEqual(describeTree("b"), "h_tiles(4 *5)")
        #expect(a.focusWorkspace())
        expectEqual(describeTree("a"), "h_tiles(*1 v_tiles(2 3))")
    }

    @Test
    func focusAfterAWindowClosesGoesToTheMostRecentWindow() { // RB-03
        let workspace = setUpTree("h_tiles(1 2)", workspace: "a") // 2 is the most recent window: it was bound last
        setUpTree("h_tiles(*3)")
        // What garbage collection does when a window closes: the closed-windows cache reads every workspace
        cacheClosedWindowIfNeeded()
        testWindow(3).closeAxWindow()
        expectEqual(workspace.children.count, 1) // The reads created no containers

        #expect(workspace.focusWorkspace())
        expectEqual(focus.windowOrNil?.windowId, 2)
    }

    @Test
    func onlyBindingCreatesContainers() { // RB-03, RB-129
        setUpTree("h_tiles(1)") // A window, so that the closed-windows cache captures the workspaces
        let workspace = Workspace.get(byName: "a")
        workspace.normalizeContainers()
        expectEqual(workspace.layoutTiling(), [])
        expectEqual(workspace.tilingWindows, [])
        expectEqual(workspace.floatingWindows, [])
        expectEqual(workspace.edgeWindow(snappedTo: .left), nil)
        expectEqual(workspace.rootLayout.layout, .tiles) // The root that the workspace would get
        expectEqual(workspace.rootLayout.orientation, .h)
        expectEqual(workspace.toLiveFocus().windowOrNil, nil)
        cacheClosedWindowIfNeeded()
        expectEqual(workspace.children.count, 0)

        // The root is created when the first window is bound, with the layout and orientation of that moment
        world.config.defaultRootContainerOrientation = .vertical
        TestWindow.new(id: 2, parent: workspace.newTilingWindowSlot().parent)
        expectEqual(describeTree("a"), "v_tiles(2)")
    }

    @Test
    func relayoutSkipsAClosedWindowAndAGarbageCollectedWorkspace() { // Stale-object policy
        let workspace = setUpTree("h_tiles(1 v_tiles(2))", workspace: "a")
        let nested = testWindow(2).parent.orDie()
        setUpTree("h_tiles(3)")
        let closed = testWindow(1)
        closed.closeAxWindow()
        testWindow(2).move(to: focus.workspace.rootTilingContainerCreatingIfNeeded())
        workspace.normalizeContainers()
        #expect(!closed.isAlive)
        #expect(!nested.isAlive)

        closed.relayoutWindow(on: focus.workspace, as: .window) // Used to crash: it's unbound
        Workspace.garbageCollectUnusedWorkspaces()
        #expect(!workspace.isAlive)
        testWindow(2).relayoutWindow(on: workspace, as: .window) // The window would be lost
        expectEqual(describeTree(), "h_tiles(3 *2)")
    }

    @Test
    func mostRecentChildIsTheLastMarkedOne() {
        let workspace = setUpTree("h_tiles(1 v_tiles(2 3) 4)", workspace: "a")
        let root = workspace.existingRootTilingContainer.orDie()
        let container = testWindow(2).parent.orDie()
        #expect(root.mostRecentChild === testWindow(4)) // Binding marks the node: the last bound child is the most recent
        expectEqual(container.mruChildren.map { ($0 as? Window)?.windowId }, [3, 2])

        testWindow(2).markAsMostRecentChild() // Marks the whole chain of parents
        #expect(root.mostRecentChild === container)
        expectEqual(container.mruChildren.map { ($0 as? Window)?.windowId }, [2, 3])
        expectEqual(root.mruChildren.map { ($0 as? Window)?.windowId }, [nil, 4, 1])
        expectEqual(workspace.mostRecentWindowRecursive?.windowId, 2)

        testWindow(2).unbindFromParent()
        #expect(container.mostRecentChild === testWindow(3))
        expectEqual(container.mruChildren.count, 1)
    }

    /// RB-77: the most recent window closes, and its empty container stays the most recent child
    @Test(arguments: [
        // The last tiling window: the most recent floating window, not the first one
        ("h_tiles(1) floating(2 3)", 1, 3),
        // The only floating window: the first window in DFS order, not the most recent one
        ("h_tiles(1 v_tiles(2 3)) floating(4)", 4, 1),
        // The only window of a nested container: the same
        ("h_tiles(1 v_tiles(2) 3)", 2, 1),
    ] as [(String, WindowId, WindowId)])
    func toLiveFocusPastAnEmptyContainer(tree: String, closedWindowId: WindowId, focused: WindowId) {
        let workspace = setUpTree(tree, workspace: "a")
        testWindow(3).markAsMostRecentChild()
        testWindow(closedWindowId).markAsMostRecentChild()
        testWindow(closedWindowId).unbindFromParent()
        expectEqual(workspace.mostRecentWindowRecursive, nil)
        expectEqual(workspace.toLiveFocus().windowOrNil?.windowId, focused)
    }

    /// Where a new tiling window goes (`layout tiling` on a floating window uses the same slot): after the most recent
    /// window if it's tiling, else at the end of the root
    @Test(arguments: [
        ("h_tiles(1 v_tiles(2 3) 4)", nil, "h_tiles(1 v_tiles(2 5 3) 4)"),
        // The only floating window (a dialog) closed. The empty floating container is the most recent child
        ("h_tiles(1 v_tiles(2 3) 4) floating(6)", 6, "h_tiles(1 v_tiles(2 3) 4 5)"),
        // The most recent window is floating
        ("h_tiles(1 v_tiles(2 3) 4) floating(6 7)", 6, "h_tiles(1 v_tiles(2 3) 4 5) floating(7)"),
    ] as [(String, WindowId?, String)])
    func newTilingWindowSlot(tree: String, closedWindowId: WindowId?, after: String) {
        let workspace = setUpTree(tree, workspace: "a")
        testWindow(2).markAsMostRecentChild()
        if let closedWindowId {
            testWindow(closedWindowId).markAsMostRecentChild()
            testWindow(closedWindowId).unbindFromParent()
        }
        let window = TestWindow.new(id: 5, parent: macosPopupWindowsContainer)
        window.relayoutWindow(on: workspace, as: .window)
        expectEqual(describeTree("a"), after)
    }

    @Test
    func canBeChild() {
        let workspace = setUpTree("h_tiles(1 v_tiles(2)) floating(3)", workspace: "a")
        let root = workspace.existingRootTilingContainer.orDie()
        let nested = testWindow(2).parent.orDie()
        let floating = workspace.containerCreatingIfNeeded(.floating)
        let window = testWindow(1)
        // Windows go into containers of any kind, and only there
        for parent in [root, nested, floating, workspace.containerCreatingIfNeeded(.macosFullscreen), macosMinimizedWindowsContainer, macosPopupWindowsContainer] {
            #expect(window.canBeChild(of: parent))
        }
        #expect(!window.canBeChild(of: workspace))
        #expect(!window.canBeChild(of: testWindow(3)))
        // Tiling containers go into workspaces (the root) and tiling containers
        #expect(nested.canBeChild(of: root) && root.canBeChild(of: workspace) && root.canBeChild(of: nested))
        #expect(!root.canBeChild(of: floating) && !root.canBeChild(of: macosMinimizedWindowsContainer) && !root.canBeChild(of: window))
        // The special containers of a workspace go only into workspaces. The global ones and workspaces are roots
        #expect(floating.canBeChild(of: workspace) && !floating.canBeChild(of: root))
        #expect(!macosPopupWindowsContainer.canBeChild(of: workspace) && !macosMinimizedWindowsContainer.canBeChild(of: workspace))
        #expect(!workspace.canBeChild(of: root) && !workspace.canBeChild(of: floating))
    }
}
