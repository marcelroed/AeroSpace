@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct MoveCommandTest {
    @Test
    func parse() {
        #expect(parseCommand("move --fail-if-fullscreen left").errorOrNil == nil)
        #expect(parseCommand("move --fail-if-macos-native-fullscreen --window-id 1 right").errorOrNil == nil)
        let args = parsedArgs("move --boundaries all-monitors-outer-frame --boundaries-action fail up", as: MoveCmdArgs.self)
        #expect(args?.direction.val == .up)
        #expect(args?.rawBoundaries == .allMonitorsOuterFrame)
        #expect(args?.rawBoundariesAction == .fail)
        #expect(parsedArgs("move left", as: MoveCmdArgs.self)?.direction.val == .left)
    }

    @Test(arguments: [
        ("move --boundaries", "ERROR: <boundary> is mandatory\nERROR: Argument '(left|down|up|right)' is mandatory"),
        ("move --boundaries-action left", "ERROR: Can't parse 'left'.\n       Possible values: (stop|fail|create-implicit-container)\nERROR: Argument '(left|down|up|right)' is mandatory"),
        ("move --boundaries-action --boundaries workspace left", "ERROR: <action> is mandatory"),
        ("move foo", "ERROR: Can't parse 'foo'.\n       Possible values: (left|down|up|right)"),
    ])
    func parseError(command: String, error: String) async {
        #expect(await runCmd(command) == .fail(error))
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
    ])
    func succeeds(before: String, command: String, after: String) async {
        setUpTree(before)
        #expect(await runCmd(command) == .ok)
        #expect(describeTree() == after)
    }

    @Test(arguments: [
        ("h_tiles(*1 2 3)", "move --boundaries-action fail left"),
        ("h_tiles(1 *2)", "move --boundaries all-monitors-outer-frame --boundaries-action fail right"),
    ])
    func fails(tree: String, command: String) async {
        setUpTree(tree)
        #expect(await runCmd(command) == .fail())
        #expect(describeTree() == tree)
    }

    @Test
    func failIfFullscreen() async {
        setUpTree("h_tiles(*1 2)")
        testWindow(1).isFullscreen = true
        #expect(await runCmd("move --fail-if-fullscreen right").exitCode == 2)
        #expect(describeTree() == "h_tiles(*1 2)")
    }

    @Test
    func failIfMacosNativeFullscreen() async {
        setUpTree("h_tiles(*1 2)")
        testWindow(1).isMacosFullscreenForTest = true
        #expect(await runCmd("move --fail-if-macos-native-fullscreen right").exitCode == 2)
        #expect(describeTree() == "h_tiles(*1 2)")
    }

    @Test
    func moveIntoTheMostRecentContainer() async {
        setUpTree("h_tiles(0 *1 v_tiles(h_tiles(2 3) 4))")
        testWindow(3).markAsMostRecentChild()
        #expect(await runCmd("move right") == .ok)
        #expect(describeTree() == "h_tiles(0 v_tiles(h_tiles(*1 2 3) 4))")
    }

    @Test
    func swapPreservesWeights() async {
        setUpTree("h_tiles(1:1 *2:2)")
        #expect(await runCmd("move left") == .ok)
        #expect(describeTree(weights: true) == "h_tiles(*2:2 1:1)")
    }

    @Test
    func moveInResetsTheWeight() async {
        setUpTree("h_tiles(0 *1:2 v_tiles(2))")
        #expect(await runCmd("move right") == .ok)
        #expect(describeTree(weights: true) == "h_tiles(0:1 v_tiles:1(2:1 *1:1))")
    }

    @Test(arguments: [("h_tiles(1 *2)", "move right"), ("h_tiles(*1 2)", "move left")])
    func moveOutWithNormalization(tree: String, command: String) async {
        config.enableNormalizationFlattenContainers = true
        setUpTree(tree)
        #expect(await runCmd(command) == .ok)
        #expect(describeTree() == tree)
    }

    @Test
    func moveAcrossMonitors_noScreens_failsWithoutBugPrompt() async {
        setUpTree("h_tiles(*1 2)")
        // No screens (e.g., during display reconfiguration) is a normal state, not a bug (RB-40)
        await $noScreensForTests.withValue(true) {
            #expect(await runCmd("move --boundaries all-monitors-outer-frame left") == .fail("Can't move the window across monitors while there are no screens"))
        }
    }
}
