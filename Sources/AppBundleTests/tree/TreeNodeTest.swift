@testable import AppBundle
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct TreeNodeTest: AeroSpaceTestSuite {
    @Test
    func testChildParentCyclicReferenceMemoryLeak() {
        let workspace = Workspace.get(byName: name) // Don't cache root node
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)

        assertTrue(window.parent != nil)
        workspace.rootTilingContainer.unbindFromParent()
        assertTrue(window.parent == nil) // TreeNode.parent is weak: nil means that the unbound root was deallocated
    }

    @Test
    func testIsEffectivelyEmpty() {
        let workspace = Workspace.get(byName: name)

        assertTrue(workspace.isEffectivelyEmpty)
        weak let window: TestWindow? = .new(id: 1, parent: workspace.rootTilingContainer)
        assertNotNil(window)
        assertTrue(!workspace.isEffectivelyEmpty)
        window!.unbindFromParent()
        assertTrue(workspace.isEffectivelyEmpty)

        // Don't save to local variable
        TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        assertTrue(!workspace.isEffectivelyEmpty)
    }

    @Test
    func testNormalizeContainers_dontRemoveRoot() {
        let workspace = Workspace.get(byName: name)
        weak let root = workspace.rootTilingContainer
        func test() {
            assertNotNil(root)
            assertTrue(root!.isEffectivelyEmpty)
            workspace.normalizeContainers()
            assertNotNil(root)
        }
        test()

        config.enableNormalizationFlattenContainers = true
        test()
    }

    @Test
    func testNormalizeContainers_singleWindowChild() {
        config.enableNormalizationFlattenContainers = true
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            TestWindow.new(id: 0, parent: $0)
            TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 1, parent: $0)
            }
        }
        workspace.normalizeContainers()
        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(0), .window(1)]))
    }

    @Test
    func testNormalizeContainers_removeEffectivelyEmpty() {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                _ = TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1)
            }
        }
        assertEquals(workspace.rootTilingContainer.children.count, 1)
        workspace.normalizeContainers()
        assertEquals(workspace.rootTilingContainer.children.count, 0)
    }

    @Test
    func testNormalizeContainers_flattenContainers() {
        let workspace = Workspace.get(byName: name) // Don't cache root node
        workspace.rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 1, parent: $0, adaptiveWeight: 1)
            }
        }
        workspace.normalizeContainers()
        assertTrue(workspace.rootTilingContainer.children.singleOrNil() is TilingContainer)

        config.enableNormalizationFlattenContainers = true
        workspace.normalizeContainers()
        assertTrue(workspace.rootTilingContainer.children.singleOrNil() is TestWindow)
    }

    @Test
    func testCreatingSpecialContainersOnReadKeepsMostRecentWindow() {
        // RB-03: reading a missing container created it as the most recent child, so toLiveFocus() fell back to the first window
        let workspace = Workspace.get(byName: name)
        TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        assertEquals(workspace.toLiveFocus().windowOrNil?.windowId, 2)

        _ = workspace.floatingWindowsContainer
        assertEquals(workspace.toLiveFocus().windowOrNil?.windowId, 2)
        _ = workspace.macOsNativeFullscreenWindowsContainer
        assertEquals(workspace.toLiveFocus().windowOrNil?.windowId, 2)
        _ = workspace.macOsNativeHiddenAppsWindowsContainer
        assertEquals(workspace.toLiveFocus().windowOrNil?.windowId, 2)
    }

    @Test
    func testCreatingRootTilingContainerOnReadKeepsMostRecentWindow() {
        let workspace = Workspace.get(byName: name)
        TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer)
        TestWindow.new(id: 2, parent: workspace.floatingWindowsContainer)
        assertEquals(workspace.toLiveFocus().windowOrNil?.windowId, 2)

        _ = workspace.rootTilingContainer
        assertEquals(workspace.toLiveFocus().windowOrNil?.windowId, 2)
    }
}
