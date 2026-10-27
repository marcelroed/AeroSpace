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

    @Test
    func isEffectivelyEmpty() {
        let workspace = focus.workspace

        #expect(workspace.isEffectivelyEmpty)
        weak let window: TestWindow? = .new(id: 1, parent: workspace.rootTilingContainerCreatingIfNeeded())
        #expect(window != nil)
        #expect(!workspace.isEffectivelyEmpty)
        window?.unbindFromParent()
        #expect(workspace.isEffectivelyEmpty)

        // Don't save to local variable
        TestWindow.new(id: 2, parent: workspace.rootTilingContainerCreatingIfNeeded())
        #expect(!workspace.isEffectivelyEmpty)
    }

    @Test(arguments: [false, true])
    func normalizeContainers_dontRemoveRoot(flattenContainers: Bool) {
        world.config.enableNormalizationFlattenContainers = flattenContainers
        let workspace = focus.workspace
        weak let root = workspace.rootTilingContainerCreatingIfNeeded()
        expectEqual(root?.isEffectivelyEmpty, true)
        workspace.normalizeContainers()
        #expect(root != nil)
    }

    @Test(arguments: [
        // Containers without windows are removed
        (false, "h_tiles(v_tiles(h_tiles()))", "h_tiles()"),
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
    }

    @Test
    func creatingSpecialContainersKeepsMostRecentWindow() {
        // RB-03: creating a container bound it as the most recent child, so toLiveFocus() fell back to the first window
        let workspace = Workspace.get(byName: "a")
        TestWindow.new(id: 1, parent: workspace.rootTilingContainerCreatingIfNeeded())
        TestWindow.new(id: 2, parent: workspace.rootTilingContainerCreatingIfNeeded())
        expectEqual(workspace.toLiveFocus().windowOrNil?.windowId, 2)

        _ = workspace.containerCreatingIfNeeded(.floating)
        expectEqual(workspace.toLiveFocus().windowOrNil?.windowId, 2)
        _ = workspace.containerCreatingIfNeeded(.macosFullscreen)
        expectEqual(workspace.toLiveFocus().windowOrNil?.windowId, 2)
        _ = workspace.containerCreatingIfNeeded(.macosHiddenApp)
        expectEqual(workspace.toLiveFocus().windowOrNil?.windowId, 2)
    }

    @Test
    func creatingRootTilingContainerKeepsMostRecentWindow() {
        let workspace = Workspace.get(byName: "a")
        TestWindow.new(id: 1, parent: workspace.containerCreatingIfNeeded(.floating))
        TestWindow.new(id: 2, parent: workspace.containerCreatingIfNeeded(.floating))
        expectEqual(workspace.toLiveFocus().windowOrNil?.windowId, 2)

        _ = workspace.rootTilingContainerCreatingIfNeeded()
        expectEqual(workspace.toLiveFocus().windowOrNil?.windowId, 2)
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
        expectEqual(workspace.toLiveFocus().windowOrNil, nil)
        cacheClosedWindowIfNeeded()
        expectEqual(workspace.children.count, 0)

        // The root is created when the first window is bound, with the layout and orientation of that moment
        world.config.defaultRootContainerOrientation = .vertical
        TestWindow.new(id: 2, parent: workspace.newTilingWindowSlot().parent)
        expectEqual(describeTree("a"), "v_tiles(2)")
    }

    @Test
    func relayoutSkipsAClosedWindowAndAGarbageCollectedWorkspace() async throws { // Stale-object policy
        let workspace = setUpTree("h_tiles(1 v_tiles(2))", workspace: "a")
        let nested = testWindow(2).parent.orDie()
        setUpTree("h_tiles(3)")
        let closed = testWindow(1)
        closed.closeAxWindow()
        testWindow(2).move(to: focus.workspace.rootTilingContainerCreatingIfNeeded())
        workspace.normalizeContainers()
        #expect(!closed.isAlive)
        #expect(!nested.isAlive)

        try await closed.relayoutWindow(on: focus.workspace, .cancellable, forceTile: true) // Used to crash: it's unbound
        Workspace.garbageCollectUnusedWorkspaces()
        #expect(!workspace.isAlive)
        try await testWindow(2).relayoutWindow(on: workspace, .cancellable, forceTile: true) // The window would be lost
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

    @Test
    func toLiveFocusSkipsAnEmptyRootContainer() { // RB-77
        let workspace = setUpTree("h_tiles(1) floating(2 3)", workspace: "a")
        testWindow(1).markAsMostRecentChild()
        testWindow(1).unbindFromParent() // The last tiling window closes. The empty root stays the most recent child
        #expect(workspace.mostRecentChild === workspace.existingRootTilingContainer)
        expectEqual(workspace.mostRecentWindowRecursive, nil)
        expectEqual(workspace.toLiveFocus().windowOrNil?.windowId, 3) // The most recent floating window, not the first one
    }

    @Test(arguments: [
        ("h_tiles(1 v_tiles(2 3)) floating(4)", 4), // The only floating window closes
        ("h_tiles(1 v_tiles(2) 3)", 2), // The only window of a nested container closes
    ] as [(String, WindowId)])
    func toLiveFocusFallsBackToTheFirstWindowPastAnEmptyContainer(tree: String, closedWindowId: WindowId) {
        let workspace = setUpTree(tree, workspace: "a")
        testWindow(3).markAsMostRecentChild()
        testWindow(closedWindowId).markAsMostRecentChild()
        testWindow(closedWindowId).unbindFromParent() // The empty container stays the most recent child
        expectEqual(workspace.mostRecentWindowRecursive, nil)
        expectEqual(workspace.toLiveFocus().windowOrNil?.windowId, 1) // The first window in DFS order, not the most recent one
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
    func newTilingWindowSlot(tree: String, closedWindowId: WindowId?, after: String) async throws {
        let workspace = setUpTree(tree, workspace: "a")
        testWindow(2).markAsMostRecentChild()
        if let closedWindowId {
            testWindow(closedWindowId).markAsMostRecentChild()
            testWindow(closedWindowId).unbindFromParent()
        }
        let window = TestWindow.new(id: 5, parent: macosPopupWindowsContainer)
        try await window.relayoutWindow(on: workspace, .cancellable, forceTile: true)
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
