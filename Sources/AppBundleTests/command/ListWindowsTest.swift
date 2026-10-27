@testable import AppBundle
import Common
import Foundation
import Testing

@Suite(.aeroSpaceGlobalState)
struct ListWindowsTest {
    @Test
    func parse() {
        #expect(parseCommand("list-windows --pid 1").errorOrNil == "Mandatory option is not specified (--focused|--all|--monitor|--workspace)")
        #expect(parseCommand("list-windows --workspace M --pid 1").errorOrNil == nil)
        #expect(parseCommand("list-windows --pid 1 --focused").errorOrNil == "--focused conflicts with other \"filtering\" flags")
        #expect(parseCommand("list-windows --pid 1 --all").errorOrNil == "--all conflicts with \"filtering\" flags. Please use '--monitor all' instead of '--all' alias")
        #expect(parseCommand("list-windows --all").errorOrNil == nil)
        #expect(parseCommand("list-windows --all --workspace M").errorOrNil == "Conflicting options: --all, --workspace")
        #expect(parseCommand("list-windows --all --focused").errorOrNil == "Conflicting options: --all, --focused")
        #expect(parseCommand("list-windows --all --count --format %{window-title}").errorOrNil == "Conflicting options: --count, --format")
        #expect(parseCommand("list-windows --all --focused --monitor mouse").errorOrNil == "Conflicting options: --all, --focused")
        #expect(parseCommand("list-windows --all --focused --monitor mouse --workspace focused").errorOrNil == "Conflicting options: --all, --focused, --workspace")
        #expect(parseCommand("list-windows --all --workspace focused").errorOrNil == "Conflicting options: --all, --workspace")
        #expect(parseCommand("list-windows --monitor mouse").errorOrNil == nil)

        // --json
        #expect(parseCommand("list-windows --all --count --json").errorOrNil == "Conflicting options: --count, --json")
        #expect(parseCommand("list-windows --all --format '%{right-padding}' --json").errorOrNil == "%{right-padding} interpolation variable is not allowed when --json is used")
        #expect(parseCommand("list-windows --all --format '%{window-title} |' --json").errorOrNil == "Only interpolation variables and spaces are allowed in '--format' when '--json' is used")
        #expect(parseCommand("list-windows --all --format '%{window-title}' --json").errorOrNil == nil)
    }

    @Test(arguments: FormatSubject.allCases)
    func interpolationVariablesConsistency(subject: FormatSubject) {
        let prefix = switch subject {
            case .window: "window-"
            case .app: "app-"
            case .workspace: "workspace"
            case .monitor: "monitor-"
        }
        let vars = FormatVar.allCases.filter { $0.subject == subject }
        #expect(!vars.isEmpty)
        #expect(vars.filter { !$0.rawValue.starts(with: prefix) } == [])
    }

    @Test
    func format() throws {
        let root = focus.workspace.rootTilingContainer
        var windows = [
            AeroObj.window(.forTest(window: TestWindow.new(id: 2, parent: root), title: "non-empty")),
            AeroObj.window(.forTest(window: TestWindow.new(id: 1, parent: root), title: "")),
        ]
        #expect(try windows.format([.interVar(.windowTitle)]) == ["non-empty", ""])

        windows = [
            AeroObj.window(.forTest(window: TestWindow.new(id: 3, parent: root), title: "non-empty")),
            AeroObj.window(.forTest(window: TestWindow.new(id: 10, parent: root), title: "")),
        ]
        #expect(try windows.format([.interVar(.windowId), .interVar(.rightPadding), .interVar(.windowTitle)]) == ["3 non-empty", "10"])

        windows = [
            AeroObj.window(.forTest(window: TestWindow.new(id: 4, parent: root), title: "title1")),
            AeroObj.window(.forTest(window: TestWindow.new(id: 11, parent: root), title: "title2")),
        ]
        #expect(try windows.format([.interVar(.windowId), .interVar(.rightPadding), .literal(" | "), .interVar(.windowTitle)]) == ["4  | title1", "11 | title2"])
    }

    @Test
    func runFocusedNoWindow() async {
        let output = await runCmd("list-windows --focused --format '%{window-id}'")
        #expect(output == .fail(noWindowIsFocused))
    }

    @Test
    func runFocusedHappy() async {
        setUpTree("h_tiles(*1 2)")
        let output = await runCmd("list-windows --focused --format '%{window-id}'")
        #expect(output == CmdOutput(stdout: ["1"]))
    }

    @Test
    func runAll() async {
        setUpTree("h_tiles(1)", workspace: "a")
        setUpTree("h_tiles(2)", workspace: "b")
        let output = await runCmd("list-windows --all --format '%{window-id}'")
        #expect(output.stdout.sorted() == ["1", "2"])
        #expect(output.stderr == [] && output.exitCode == 0)
    }

    @Test
    func runAll_windowsOfTheSameAppAndTitleAreOrderedByWorkspace() async {
        // The title isn't fetched for this format, so all the windows tie on the app name and the title. The windows
        // are collected from a Set of workspaces, whose order is random, and ten of them make it fail reliably (RB-13).
        // The IDs go down while the workspaces go up (in logical order: w2 < w10), so ordering by ID fails too
        for index: UInt32 in (1 ... 10).reversed() {
            setUpTree("h_tiles(\(11 - index))", workspace: "w\(index)")
        }
        let output = await runCmd("list-windows --all --format '%{window-id}'")
        #expect(output == CmdOutput(stdout: (1 ... 10).reversed().map(String.init)))
    }

    @Test
    func runWorkspace_windowsOfTheSameAppAndTitleAreInTreeOrder() async {
        // Tree order differs from ID order. Within one workspace, tied windows are listed in tree order (RB-13)
        setUpTree("h_tiles(3 v_tiles(1) 2)", workspace: "a")
        let output = await runCmd("list-windows --workspace a --format '%{window-id}'")
        #expect(output == CmdOutput(stdout: ["3", "1", "2"]))
    }

    @Test
    func runCount() async {
        setUpTree("h_tiles(1 2)", workspace: "a")
        setUpTree("h_tiles(3)", workspace: "b")
        let output = await runCmd("list-windows --all --count")
        #expect(output == CmdOutput(stdout: ["3"]))
    }

    @Test
    func runJson() async {
        setUpTree("h_tiles(7)", workspace: "a")
        let expected = JSONEncoder.aeroSpaceDefault.encodeToString([["window-id": 7]])
        let output = await runCmd("list-windows --all --format '%{window-id}' --json")
        #expect(output == CmdOutput(stdout: [expected.orDie()]))
    }

    @Test
    func runFilterByWorkspaceName() async {
        setUpTree("h_tiles(1)", workspace: "a")
        setUpTree("h_tiles(2)", workspace: "b")
        let output = await runCmd("list-windows --workspace a --format '%{window-id}'")
        #expect(output == CmdOutput(stdout: ["1"]))
    }

    @Test
    func runFilterByWorkspaceFocused() async {
        let workspaceA = setUpTree("h_tiles(1)", workspace: "a")
        setUpTree("h_tiles(2)", workspace: "b")
        #expect(workspaceA.focusWorkspace())
        let output = await runCmd("list-windows --workspace focused --format '%{window-id}'")
        #expect(output == CmdOutput(stdout: ["1"]))
    }

    @Test
    func runFilterByWorkspaceVisible() async {
        let workspaceA = setUpTree("h_tiles(1)", workspace: "a")
        setUpTree("h_tiles(2)", workspace: "b")
        #expect(workspaceA.focusWorkspace())
        let output = await runCmd("list-windows --workspace visible --format '%{window-id}'")
        #expect(output == CmdOutput(stdout: ["1"]))
    }

    @Test
    func runFilterByMonitor() async {
        setUpTree("h_tiles(1)", workspace: "a")
        let output = await runCmd("list-windows --monitor focused --format '%{window-id}'")
        #expect(output == CmdOutput(stdout: ["1"]))
    }

    @Test
    func runInvalidMonitor() async {
        setUpTree("h_tiles(1)", workspace: "a")
        let output = await runCmd("list-windows --monitor 99 --format '%{window-id}'")
        #expect(output == .fail("Invalid monitor ID: 99"))
    }

    @Test
    func runFilterByPid() async {
        setUpTree("h_tiles(1)", workspace: "a")
        var output = await runCmd("list-windows --monitor all --pid 0 --format '%{window-id}'")
        #expect(output == CmdOutput(stdout: ["1"]))

        output = await runCmd("list-windows --monitor all --pid 9999 --format '%{window-id}'")
        #expect(output == .ok)
    }

    @Test
    func runFilterByAppBundleId() async {
        setUpTree("h_tiles(1)", workspace: "a")
        var output = await runCmd("list-windows --monitor all --app-bundle-id bobko.AeroSpace.test-app --format '%{window-id}'")
        #expect(output == CmdOutput(stdout: ["1"]))

        output = await runCmd("list-windows --monitor all --app-bundle-id com.unknown.app --format '%{window-id}'")
        #expect(output == .ok)
    }
}
