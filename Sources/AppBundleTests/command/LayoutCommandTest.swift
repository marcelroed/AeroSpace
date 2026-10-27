@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct LayoutCommandTest {
    @Test
    func parse() async {
        for command in ["layout v_tiles h_tiles", "layout tiling", "layout floating tiling", "layout --window-id 1 horizontal vertical"] {
            #expect(parseCommand(command).errorOrNil == nil)
        }
        testParseSingleCommandSucc(
            "layout --root accordion tiles",
            LayoutCmdArgs(rawArgs: [], toggleBetween: [.accordion, .tiles]).copy(\.root, true),
        )
        testParseSingleCommandSucc(
            "layout --for-next-detected-window floating",
            LayoutCmdArgs(rawArgs: [], toggleBetween: [.floating]).copy(\.forNextDetectedWindow, true),
        )
        for command in ["layout --for-next-detected-window floating tiling", "layout --for-next-detected-window accordion"] {
            let output = await runCmd(command)
            #expect(output == .fail("ERROR: " + layoutCommandForNextDetectedWindowFlagIncompatibilityMsg))
        }
    }

    @Test(arguments: [
        ("layout --root accordion tiling", "ERROR: layout command: --root and tiling|floating are incompatible"),
        ("layout --workspace 2 tiles", "ERROR: --workspace flag requires using an explicit --root flag"),
        ("layout --workspace 2 --window-id 2 tiles", "ERROR: Conflicting options: --window-id, --workspace"),
        ("layout --fail-if-noop accordion tiling", "ERROR: --fail-if-noop allows only one <target-layout> argument"),
        ("layout --for-next-detected-window --window-id 1 floating", "ERROR: Conflicting options: --for-next-detected-window, --window-id"),
        ("layout --for-next-detected-window --workspace 2 floating", "ERROR: Conflicting options: --for-next-detected-window, --workspace"),
        ("layout --for-next-detected-window --root floating", "ERROR: Conflicting options: --for-next-detected-window, --root"),
        ("layout --for-next-detected-window --fail-if-noop floating", "ERROR: Conflicting options: --fail-if-noop, --for-next-detected-window"),
    ])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        #expect(output == .fail(error))
    }

    @Test(arguments: [
        ("h_tiles(*1 2)", "layout vertical", "v_tiles(*1 2)"),
        ("h_tiles(*1 2)", "layout accordion", "h_accordion(*1 2)"),
        ("h_tiles(*1 2)", "layout v_accordion", "v_accordion(*1 2)"),
        // Toggles to the first layout that doesn't match
        ("h_tiles(*1 2)", "layout h_tiles h_accordion", "h_accordion(*1 2)"),
        ("h_tiles(*1 2)", "layout floating", "h_tiles(2) floating(*1)"),
        ("h_tiles() floating(*1)", "layout tiling", "h_tiles(*1)"),
        ("h_tiles() floating(*1)", "layout floating tiling", "h_tiles(*1)"),
        ("h_tiles(*1)", "layout floating tiling", "h_tiles() floating(*1)"),
        // --root changes the root container instead of the parent of the window
        ("h_tiles(v_tiles(*1) 2)", "layout --root v_accordion", "v_accordion(v_tiles(*1) 2)"),
        ("h_tiles(v_tiles(*1) 2)", "layout --root h_tiles h_accordion", "h_accordion(v_tiles(*1) 2)"),
        ("h_tiles() floating(*1)", "layout --root v_accordion", "v_accordion() floating(*1)"),
        // Without --root, it fails: "Can't change layout for macOS minimized, fullscreen…"
        ("h_tiles() macos_fullscreen(*1)", "layout --root v_accordion", "v_accordion() macos_fullscreen(*1)"),
        // Changes nothing until a window is detected
        ("h_tiles(*1)", "layout floating --for-next-detected-window", "h_tiles(*1)"),
    ])
    func succeeds(before: String, command: String, after: String) async {
        setUpTree(before)
        let output = await runCmd(command)
        #expect(output == .ok)
        #expect(describeTree() == after)
    }

    /// The window goes to the end of the root, not after the most recent tiling window
    @Test(arguments: [
        ("v_tiles(*1 2) floating(3)", 3 as UInt32, "v_tiles(1 2 *3)"),
        ("h_tiles(6 v_tiles(*7)) floating(9)", 9, "h_tiles(6 v_tiles(7) *9)"),
        ("v_tiles(*1 2) floating(3 4)", 3, "v_tiles(1 2 *3) floating(4)"), // With another floating window
    ], ["layout tiling", "layout floating tiling"])
    func tilingOnFloatingWindow(tree: (before: String, floatingWindowId: UInt32, after: String), command: String) async {
        setUpTree(tree.before)
        #expect(testWindow(tree.floatingWindowId).focusWindow())
        let output = await runCmd(command)
        #expect(output == .ok)
        #expect(describeTree() == tree.after)
    }

    @Test(arguments: [
        ("h_tiles(*1 2)", "layout h_tiles", alreadyIn("h_tiles")),
        ("h_tiles(*1 2)", "layout tiling", alreadyIn("tiling")),
        ("h_tiles(*1 2)", "layout --root h_tiles", alreadyIn("h_tiles")),
        ("h_tiles() floating(*1)", "layout floating", alreadyIn("floating")),
    ])
    func noop(tree: String, command: String, expected: CmdOutput) async {
        setUpTree(tree)
        let output = await runCmd(command)
        #expect(output == expected)
        #expect(describeTree() == tree)
    }

    /// AEROSPACE_WORKSPACE names the empty focused workspace. A non-visible empty workspace would be garbage collected
    @Test(arguments: [
        ("layout v_tiles", CmdOutput.ok, "v_tiles()"),
        ("layout accordion", .ok, "h_accordion()"),
        ("layout --root accordion", .ok, "h_accordion()"),
        ("layout h_tiles", alreadyIn("h_tiles"), "h_tiles()"),
        ("layout tiling", alreadyIn("tiling"), "h_tiles()"),
        ("layout tiling --fail-if-noop", .fail(), "h_tiles()"),
        ("layout floating", .fail("No window is focused"), "h_tiles()"),
    ])
    func emptyWorkspace(command: String, expected: CmdOutput, after: String) async {
        let workspace = setUpTree("h_tiles()")
        let output = await runCmd(command, workspaceEnv: workspace.name)
        #expect(output == expected)
        #expect(describeTree() == after)
    }

    @Test(arguments: ["--window-id 2", "--workspace b"])
    func rootOfAnotherWorkspace(flag: String) async {
        setUpTree("h_tiles(*1)", workspace: "a")
        setUpTree("h_tiles(2)", workspace: "b")
        let output = await runCmd("layout --root \(flag) v_accordion")
        #expect(output == .ok)
        #expect(describeTree("b") == "v_accordion(2)")
        #expect(describeTree("a") == "h_tiles(*1)") // The focused workspace is untouched
    }

    @Test(arguments: tilingDescriptions, ["h_tiles", "v_tiles", "h_accordion", "v_accordion"])
    func tilingDescription(_ description: TilingDescription, start: String) async {
        setUpTree("\(start)(*1 2)")
        let startParts = start.split(separator: "_").map(String.init)
        let expected = (description.orientation ?? startParts[0]) + "_" + (description.layout ?? startParts[1])
        let output = await runCmd("layout \(description.name)")
        #expect(output == (expected == start ? alreadyIn(description.name) : .ok))
        #expect(describeTree() == "\(expected)(*1 2)")
    }

    @Test(arguments: tilingDescriptions)
    func tilingDescription_onFloatingWindow_fails(_ description: TilingDescription) async {
        setUpTree("h_tiles() floating(*1)")
        let output = await runCmd("layout \(description.name)")
        #expect(output == .fail("The window is non-tiling"))
        #expect(describeTree() == "h_tiles() floating(*1)")
    }

    @Test
    func forNextDetectedWindow_appliesToTheNextDetectedWindowOnly() async {
        let workspace = setUpTree("h_tiles(*1)")
        let output = await runCmd("layout floating --for-next-detected-window")
        #expect(output == .ok)

        await runOnWindowDetected(ifConventional: TestWindow.new(id: 2, parent: workspace.rootTilingContainer))
        #expect(describeTree() == "h_tiles(*1) floating(2)")

        await runOnWindowDetected(ifConventional: TestWindow.new(id: 3, parent: workspace.rootTilingContainer))
        #expect(describeTree() == "h_tiles(*1 3) floating(2)")
    }

    @Test
    func forNextDetectedWindow_secondInvocationReplacesTheScheduledLayout() async {
        let workspace = setUpTree("h_tiles(*1)")
        var output = await runCmd("layout floating --for-next-detected-window")
        #expect(output == .ok)
        output = await runCmd("layout tiling --for-next-detected-window")
        #expect(output == .ok)
        // The window is detected as floating. The replaced 'floating' would have been a noop, 'tiling' tiles it
        await runOnWindowDetected(ifConventional: TestWindow.new(id: 2, parent: workspace.floatingWindowsContainer))
        #expect(describeTree() == "h_tiles(*1 2)")
    }

    @Test
    func forNextDetectedWindow_appliedBeforeAndAfterOnWindowDetectedCallbacks() async {
        let workspace = setUpTree("h_tiles(*1)")
        config.onWindowDetected = [
            WindowDetectedCallback(matcher: .command(.empty), run: parseCommand("layout floating tiling").cmdOrDie), // matches every window
        ]
        let output = await runCmd("layout floating --for-next-detected-window")
        #expect(output == .ok)
        await runOnWindowDetected(ifConventional: TestWindow.new(id: 2, parent: workspace.rootTilingContainer))
        #expect(describeTree() == "h_tiles(*1) floating(2)")
    }

    /// A tiling layout description, with the orientation and the layout it requests (nil: keep the current one)
    nonisolated struct TilingDescription: Sendable, CustomTestStringConvertible {
        let name: String
        let orientation: String?
        let layout: String?

        var testDescription: String { name }
    }
}

nonisolated private let tilingDescriptions: [LayoutCommandTest.TilingDescription] = [
    .init(name: "h_accordion", orientation: "h", layout: "accordion"),
    .init(name: "v_accordion", orientation: "v", layout: "accordion"),
    .init(name: "h_tiles", orientation: "h", layout: "tiles"),
    .init(name: "v_tiles", orientation: "v", layout: "tiles"),
    .init(name: "accordion", orientation: nil, layout: "accordion"),
    .init(name: "tiles", orientation: nil, layout: "tiles"),
    .init(name: "horizontal", orientation: "h", layout: nil),
    .init(name: "vertical", orientation: "v", layout: nil),
]

nonisolated private func alreadyIn(_ mode: String) -> CmdOutput {
    CmdOutput(stderr: ["Already in the requested \(mode) mode. Tip: use --fail-if-noop to exit with non-zero code"])
}
