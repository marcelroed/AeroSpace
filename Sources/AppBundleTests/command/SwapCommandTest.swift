@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct SwapCommandTest: AeroSpaceTestSuite {
    @Test
    func testSwap_swapWindows_Directional() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
            }
            TestWindow.new(id: 3, parent: $0)
        }

        await assertSwap("swap right", root, .h_tiles([.v_tiles([.window(3), .window(2)]), .window(1)]), focused: 1)
        await assertSwap("swap left", root, .h_tiles([.v_tiles([.window(1), .window(2)]), .window(3)]), focused: 1)
        await assertSwap("swap down", root, .h_tiles([.v_tiles([.window(2), .window(1)]), .window(3)]), focused: 1)
        await assertSwap("swap up", root, .h_tiles([.v_tiles([.window(1), .window(2)]), .window(3)]), focused: 1)
    }

    @Test
    func testSwap_swapWindows_DfsRelative() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
            }
            TestWindow.new(id: 3, parent: $0)
        }

        await assertSwap("swap dfs-next", root, .h_tiles([.v_tiles([.window(2), .window(1)]), .window(3)]), focused: 1)
        await assertSwap("swap dfs-next", root, .h_tiles([.v_tiles([.window(2), .window(3)]), .window(1)]), focused: 1)
        await assertSwap("swap dfs-prev", root, .h_tiles([.v_tiles([.window(2), .window(1)]), .window(3)]), focused: 1)
        await assertSwap("swap dfs-prev", root, .h_tiles([.v_tiles([.window(1), .window(2)]), .window(3)]), focused: 1)
    }

    @Test
    func testSwap_DirectionalWrapping() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }

        await assertSwap("swap --wrap-around left", root, .h_tiles([.window(3), .window(2), .window(1)]), focused: 1)
        await assertSwap("swap --wrap-around right", root, .h_tiles([.window(1), .window(2), .window(3)]), focused: 1)
    }

    @Test
    func testSwap_DfsRelativeWrapping() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }

        await assertSwap("swap --wrap-around dfs-prev", root, .h_tiles([.window(3), .window(2), .window(1)]), focused: 1)
        await assertSwap("swap --wrap-around dfs-next", root, .h_tiles([.window(1), .window(2), .window(3)]), focused: 1)
    }

    @Test
    func testSwap_SwapFocus() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            TestWindow.new(id: 3, parent: $0)
        }

        await assertSwap("swap --swap-focus right", root, .h_tiles([.window(1), .window(3), .window(2)]), focused: 3)
    }

    /// Runs `command`, then checks the layout of `root` and that window `focused` is both focused and the most recent one
    private func assertSwap(
        _ command: String,
        _ root: TilingContainer,
        _ expected: LayoutDescription,
        focused: UInt32,
        fileID: String = #fileID,
        filePath: StaticString = #filePath,
        line: Int = #line,
        column: Int = #column,
    ) async {
        await parseCommand(command).cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, expected, fileID: fileID, filePath: filePath, line: line, column: column)
        assertEquals(focus.windowOrNil?.windowId, focused, fileID: fileID, filePath: filePath, line: line, column: column)
        assertEquals(root.mostRecentWindowRecursive?.windowId, focused, fileID: fileID, filePath: filePath, line: line, column: column)
    }
}
