@testable import AppBundle
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct TreeNodeTest {
    @Test
    func childParentCyclicReferenceMemoryLeak() {
        let workspace = focus.workspace // Don't cache root node
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)

        #expect(window.parent != nil)
        workspace.rootTilingContainer.unbindFromParent()
        #expect(window.parent == nil) // TreeNode.parent is weak: nil means that the unbound root was deallocated
    }

    @Test
    func isEffectivelyEmpty() {
        let workspace = focus.workspace

        #expect(workspace.isEffectivelyEmpty)
        weak let window: TestWindow? = .new(id: 1, parent: workspace.rootTilingContainer)
        #expect(window != nil)
        #expect(!workspace.isEffectivelyEmpty)
        window?.unbindFromParent()
        #expect(workspace.isEffectivelyEmpty)

        // Don't save to local variable
        TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        #expect(!workspace.isEffectivelyEmpty)
    }

    @Test(arguments: [false, true])
    func normalizeContainers_dontRemoveRoot(flattenContainers: Bool) {
        config.enableNormalizationFlattenContainers = flattenContainers
        let workspace = focus.workspace
        weak let root = workspace.rootTilingContainer
        #expect(root?.isEffectivelyEmpty == true)
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
    ])
    func normalizeContainers(flattenContainers: Bool, before: String, after: String) {
        config.enableNormalizationFlattenContainers = flattenContainers
        let workspace = setUpTree(before, workspace: "a")
        workspace.normalizeContainers()
        #expect(describeTree("a") == after)
    }

    @Test
    func creatingSpecialContainersOnReadKeepsMostRecentWindow() {
        // RB-03: reading a missing container created it as the most recent child, so toLiveFocus() fell back to the first window
        let workspace = Workspace.get(byName: "a")
        TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        #expect(workspace.toLiveFocus().windowOrNil?.windowId == 2)

        _ = workspace.floatingWindowsContainer
        #expect(workspace.toLiveFocus().windowOrNil?.windowId == 2)
        _ = workspace.macOsNativeFullscreenWindowsContainer
        #expect(workspace.toLiveFocus().windowOrNil?.windowId == 2)
        _ = workspace.macOsNativeHiddenAppsWindowsContainer
        #expect(workspace.toLiveFocus().windowOrNil?.windowId == 2)
    }

    @Test
    func creatingRootTilingContainerOnReadKeepsMostRecentWindow() {
        let workspace = Workspace.get(byName: "a")
        TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer)
        TestWindow.new(id: 2, parent: workspace.floatingWindowsContainer)
        #expect(workspace.toLiveFocus().windowOrNil?.windowId == 2)

        _ = workspace.rootTilingContainer
        #expect(workspace.toLiveFocus().windowOrNil?.windowId == 2)
    }

    @Test
    func mostRecentChildIsTheLastMarkedOne() {
        let workspace = setUpTree("h_tiles(1 v_tiles(2 3) 4)", workspace: "a")
        let root = workspace.rootTilingContainer
        let container = testWindow(2).parent.orDie()
        #expect(root.mostRecentChild === testWindow(4)) // Binding marks the node: the last bound child is the most recent
        #expect(container.mruChildren.map { ($0 as? Window)?.windowId } == [3, 2])

        testWindow(2).markAsMostRecentChild() // Marks the whole chain of parents
        #expect(root.mostRecentChild === container)
        #expect(container.mruChildren.map { ($0 as? Window)?.windowId } == [2, 3])
        #expect(root.mruChildren.map { ($0 as? Window)?.windowId } == [nil, 4, 1])
        #expect(workspace.mostRecentWindowRecursive?.windowId == 2)

        testWindow(2).unbindFromParent()
        #expect(container.mostRecentChild === testWindow(3))
        #expect(container.mruChildren.count == 1)
    }
}
