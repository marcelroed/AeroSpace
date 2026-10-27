@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct MoveCommandTest {
    @Test
    func parse() {
        expectEqual(parseCommand("move --fail-if-fullscreen left").errorOrNil, nil)
        expectEqual(parseCommand("move --fail-if-macos-native-fullscreen --window-id 1 right").errorOrNil, nil)
        let args = parsedCmd("move --boundaries all-monitors-outer-frame --boundaries-action fail up", as: MoveCommand.self)
        expectEqual(args?.direction, .up)
        expectEqual(args?.boundaries, .allMonitorsOuterFrame)
        expectEqual(args?.boundariesAction, .fail)
        expectEqual(parsedCmd("move left", as: MoveCommand.self)?.direction, .left)
    }

    @Test(arguments: [
        ("move --boundaries", "'--boundaries' must be followed by '<boundary>'"),
        ("move --boundaries-action left", "Can't parse 'left'.\nPossible values: (stop|fail|create-implicit-container)"),
        ("move --boundaries-action --boundaries workspace left", "'--boundaries-action' must be followed by '<action>'"),
        ("move foo", "Can't parse 'foo'.\nPossible values: (left|down|up|right)"),
    ] as [(String, String)])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        expectEqual(output, .fail(error))
    }

    @Test(arguments: [
        // Swaps with the sibling
        ("h_tiles(*1 2)", "move right", "h_tiles(2 *1)"),
        ("h_tiles(*1 2)", "move --fail-if-fullscreen --fail-if-macos-native-fullscreen right", "h_tiles(2 *1)"),
        // Moves into the top-most container with the right orientation
        ("h_tiles(0 *1 h_tiles(h_tiles(2)))", "move right", "h_tiles(0 h_tiles(*1 h_tiles(2)))"),
        // Moves out of the container
        ("h_tiles(1 v_tiles(*2 3 4))", "move left", "h_tiles(1 *2 v_tiles(3 4))"),
        // At the root, across its orientation: the window goes to a new root with the old root as its sibling
        ("h_tiles(1 *2 3)", "move up", "v_tiles(*2 h_tiles(1 3))"),
        ("h_tiles(*1 2 3)", "move --boundaries-action stop left", "h_tiles(*1 2 3)"),
        ("h_tiles(*1 2 3)", "move --boundaries-action stop up", "h_tiles(*1 2 3)"),
        ("h_tiles(1 *2 3)", "move --boundaries-action stop left", "h_tiles(*2 1 3)"),
        ("h_tiles(1 v_tiles(*2 3))", "move --boundaries-action stop right", "h_tiles(1 v_tiles(3) *2)"),
        // The test monitor is the only monitor, so there is never a monitor in the direction of the move
        ("h_tiles(*1 2)", "move --boundaries all-monitors-outer-frame --boundaries-action stop left", "h_tiles(*1 2)"),
        ("h_tiles(*1 2)", "move --boundaries all-monitors-outer-frame --boundaries-action create-implicit-container left", "h_tiles(*1 h_tiles(2))"),
        ("h_tiles(*1 2)", "move --boundaries all-monitors-outer-frame down", "v_tiles(h_tiles(2) *1)"),
    ] as [(String, String, String)])
    func succeeds(before: String, command: String, after: String) async {
        setUpTree(before)
        let output = await runCmd(command)
        expectEqual(output, .ok)
        expectEqual(describeTree(), after)
    }

    @Test(arguments: [
        ("h_tiles(*1 2 3)", "move --boundaries-action fail left"),
        ("h_tiles(1 *2)", "move --boundaries all-monitors-outer-frame --boundaries-action fail right"),
    ] as [(String, String)])
    func fails(tree: String, command: String) async {
        setUpTree(tree)
        let output = await runCmd(command)
        expectEqual(output, .fail())
        expectEqual(describeTree(), tree)
    }

    @Test
    func failIfFullscreen() async {
        setUpTree("h_tiles(*1 2)")
        testWindow(1).isFullscreen = true
        let output = await runCmd("move --fail-if-fullscreen right")
        expectEqual(output, .fail())
        expectEqual(describeTree(), "h_tiles(*1 2)")
    }

    @Test
    func failIfMacosNativeFullscreen() async {
        setUpTree("h_tiles(*1 2)")
        testWindow(1).isMacosFullscreenForTest = true
        let output = await runCmd("move --fail-if-macos-native-fullscreen right")
        expectEqual(output, .fail())
        expectEqual(describeTree(), "h_tiles(*1 2)")
    }

    @Test
    func moveIntoTheMostRecentContainer() async {
        setUpTree("h_tiles(0 *1 v_tiles(h_tiles(2 3) 4))")
        testWindow(3).markAsMostRecentChild()
        let output = await runCmd("move right")
        expectEqual(output, .ok)
        expectEqual(describeTree(), "h_tiles(0 v_tiles(h_tiles(*1 2 3) 4))")
    }

    @Test
    func swapPreservesWeights() async {
        setUpTree("h_tiles(1:1 *2:2)")
        let output = await runCmd("move left")
        expectEqual(output, .ok)
        expectEqual(describeTree(weights: true), "h_tiles(*2:2 1:1)")
    }

    @Test
    func moveInResetsTheWeight() async {
        setUpTree("h_tiles(0 *1:2 v_tiles(2))")
        let output = await runCmd("move right")
        expectEqual(output, .ok)
        expectEqual(describeTree(weights: true), "h_tiles(0:1 v_tiles:1(2:1 *1:1))")
    }

    @Test(arguments: [("h_tiles(1 *2)", "move right"), ("h_tiles(*1 2)", "move left")])
    func moveOutWithNormalization(tree: String, command: String) async {
        world.config.enableNormalizationFlattenContainers = true
        setUpTree(tree)
        let output = await runCmd(command)
        expectEqual(output, .ok)
        expectEqual(describeTree(), tree)
    }

    @Test
    func moveAcrossMonitors_noScreens_failsWithoutBugPrompt() async {
        setUpTree("h_tiles(*1 2)")
        // No screens (e.g., during display reconfiguration) is a normal state, not a bug (RB-40)
        updateMonitors([])
        let output = await runCmd("move --boundaries all-monitors-outer-frame left")
        expectEqual(output, .fail("Can't find monitors in direction left while there are no screens"))
    }
}
