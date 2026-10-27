@testable import AppBundle
import Common
import XCTest

@MainActor
final class ListWindowsTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        assertEquals(parseCommand("list-windows --pid 1").errorOrNil, "ERROR: Mandatory option is not specified (--focused|--all|--monitor|--workspace)")
        assertNil(parseCommand("list-windows --workspace M --pid 1").errorOrNil)
        assertEquals(parseCommand("list-windows --pid 1 --focused").errorOrNil, "ERROR: --focused conflicts with other \"filtering\" flags")
        assertEquals(parseCommand("list-windows --pid 1 --all").errorOrNil, "ERROR: --all conflicts with \"filtering\" flags. Please use '--monitor all' instead of '--all' alias")
        assertNil(parseCommand("list-windows --all").errorOrNil)
        assertEquals(parseCommand("list-windows --all --workspace M").errorOrNil, "ERROR: Conflicting options: --all, --workspace")
        assertEquals(parseCommand("list-windows --all --focused").errorOrNil, "ERROR: Conflicting options: --all, --focused")
        assertEquals(parseCommand("list-windows --all --count --format %{window-title}").errorOrNil, "ERROR: Conflicting options: --count, --format")
        assertEquals(
            parseCommand("list-windows --all --focused --monitor mouse").errorOrNil,
            "ERROR: Conflicting options: --all, --focused")
        assertEquals(
            parseCommand("list-windows --all --focused --monitor mouse --workspace focused").errorOrNil,
            "ERROR: Conflicting options: --all, --focused, --workspace")
        assertEquals(
            parseCommand("list-windows --all --workspace focused").errorOrNil,
            "ERROR: Conflicting options: --all, --workspace")
        assertNil(parseCommand("list-windows --monitor mouse").errorOrNil)

        // --json
        assertEquals(parseCommand("list-windows --all --count --json").errorOrNil, "ERROR: Conflicting options: --count, --json")
        assertEquals(parseCommand("list-windows --all --format '%{right-padding}' --json").errorOrNil, "ERROR: %{right-padding} interpolation variable is not allowed when --json is used")
        assertEquals(parseCommand("list-windows --all --format '%{window-title} |' --json").errorOrNil, "ERROR: Only interpolation variables and spaces are allowed in \'--format\' when \'--json\' is used")
        assertNil(parseCommand("list-windows --all --format '%{window-title}' --json").errorOrNil)
    }

    func testInterpolationVariablesConsistency() {
        for kind in AeroObjKind.allCases {
            switch kind {
                case .window:
                    assertTrue(FormatVar.WindowFormatVar.allCases.allSatisfy { $0.rawValue.starts(with: "window-") })
                case .app:
                    assertTrue(FormatVar.AppFormatVar.allCases.allSatisfy { $0.rawValue.starts(with: "app-") })
                case .workspace:
                    assertTrue(FormatVar.WorkspaceFormatVar.allCases.allSatisfy { $0.rawValue.starts(with: "workspace") })
                case .monitor:
                    assertTrue(FormatVar.MonitorFormatVar.allCases.allSatisfy { $0.rawValue.starts(with: "monitor-") })
            }
        }
    }

    func testFormat() {
        Workspace.get(byName: name).rootTilingContainer.apply {
            let windows = [
                AeroObj.window(.forTest(window: TestWindow.new(id: 2, parent: $0), title: "non-empty")),
                AeroObj.window(.forTest(window: TestWindow.new(id: 1, parent: $0), title: "")),
            ]
            assertSucc(windows.format([.interVar(.formatVar(.window(.windowTitle)))]), ["non-empty", ""])
        }

        Workspace.get(byName: name).rootTilingContainer.apply {
            let windows = [
                AeroObj.window(.forTest(window: TestWindow.new(id: 3, parent: $0), title: "non-empty")),
                AeroObj.window(.forTest(window: TestWindow.new(id: 10, parent: $0), title: "")),
            ]
            assertSucc(windows.format([.interVar(.formatVar(.window(.windowId))), .interVar(.plainInterVar(.rightPadding)), .interVar(.formatVar(.window(.windowTitle)))]), ["3 non-empty", "10"])
        }

        Workspace.get(byName: name).rootTilingContainer.apply {
            let windows = [
                AeroObj.window(.forTest(window: TestWindow.new(id: 4, parent: $0), title: "title1")),
                AeroObj.window(.forTest(window: TestWindow.new(id: 11, parent: $0), title: "title2")),
            ]
            assertSucc(windows.format([.interVar(.formatVar(.window(.windowId))), .interVar(.plainInterVar(.rightPadding)), .literal(" | "), .interVar(.formatVar(.window(.windowTitle)))]), ["4  | title1", "11 | title2"])
        }
    }

    func testRunFocusedNoWindow() async {
        let result = await parseCommand("list-windows --focused --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, [noWindowIsFocused])
        assertEquals(result.stdout, [])
    }

    func testRunFocusedHappy() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }
        let result = await parseCommand("list-windows --focused --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, [])
        assertEquals(result.stdout, ["1"])
    }

    func testRunAll() async {
        TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        TestWindow.new(id: 2, parent: Workspace.get(byName: "b").rootTilingContainer)
        let result = await parseCommand("list-windows --all --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, [])
        assertEquals(result.stdout.sorted(), ["1", "2"])
    }

    func testRunAll_windowsOfTheSameAppAndTitleAreOrderedByWorkspace() async {
        // The title isn't fetched for this format, so all the windows tie on the app name and the title. The windows
        // are collected from a Set of workspaces, whose order is random, and ten of them make it fail reliably (RB-13).
        // The IDs go down while the workspaces go up (in logical order: w2 < w10), so ordering by ID fails too
        for index: UInt32 in (1 ... 10).reversed() {
            TestWindow.new(id: 11 - index, parent: Workspace.get(byName: "w\(index)").rootTilingContainer)
        }
        let result = await parseCommand("list-windows --all --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stdout, (1 ... 10).reversed().map(String.init))
    }

    func testRunWorkspace_windowsOfTheSameAppAndTitleAreInTreeOrder() async {
        // Tree order differs from ID order. Within one workspace, tied windows are listed in tree order (RB-13)
        Workspace.get(byName: "a").rootTilingContainer.apply {
            TestWindow.new(id: 3, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 1, parent: $0)
            }
            TestWindow.new(id: 2, parent: $0)
        }
        let result = await parseCommand("list-windows --workspace a --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stdout, ["3", "1", "2"])
    }

    func testRunCount() async {
        let workspace = Workspace.get(byName: "a")
        TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        TestWindow.new(id: 3, parent: Workspace.get(byName: "b").rootTilingContainer)
        let result = await parseCommand("list-windows --all --count").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stdout, ["3"])
    }

    func testRunJson() async {
        TestWindow.new(id: 7, parent: Workspace.get(byName: "a").rootTilingContainer)
        let result = await parseCommand("list-windows --all --format '%{window-id}' --json").cmdOrDie.run(.defaultEnv, .emptyStdin)
        let expected = JSONEncoder.aeroSpaceDefault.encodeToString([["window-id": 7]])
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stdout, [expected])
    }

    func testRunFilterByWorkspaceName() async {
        TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        TestWindow.new(id: 2, parent: Workspace.get(byName: "b").rootTilingContainer)
        let result = await parseCommand("list-windows --workspace a --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stdout, ["1"])
    }

    func testRunFilterByWorkspaceFocused() async {
        let workspaceA = Workspace.get(byName: "a")
        TestWindow.new(id: 1, parent: workspaceA.rootTilingContainer)
        TestWindow.new(id: 2, parent: Workspace.get(byName: "b").rootTilingContainer)
        assertEquals(workspaceA.focusWorkspace(), true)
        let result = await parseCommand("list-windows --workspace focused --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stdout, ["1"])
    }

    func testRunFilterByWorkspaceVisible() async {
        let workspaceA = Workspace.get(byName: "a")
        TestWindow.new(id: 1, parent: workspaceA.rootTilingContainer)
        TestWindow.new(id: 2, parent: Workspace.get(byName: "b").rootTilingContainer)
        assertEquals(workspaceA.focusWorkspace(), true)
        let result = await parseCommand("list-windows --workspace visible --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stdout, ["1"])
    }

    func testRunFilterByMonitor() async {
        TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        let result = await parseCommand("list-windows --monitor focused --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stdout, ["1"])
    }

    func testRunInvalidMonitor() async {
        TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        let result = await parseCommand("list-windows --monitor 99 --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stdout, [])
        assertEquals(result.stderr, ["Invalid monitor ID: 99"])
    }

    func testRunFilterByPid() async {
        TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        let matching = await parseCommand("list-windows --monitor all --pid 0 --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(matching.exitCode.rawValue, 0)
        assertEquals(matching.stdout, ["1"])

        let mismatching = await parseCommand("list-windows --monitor all --pid 9999 --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(mismatching.exitCode.rawValue, 0)
        assertEquals(mismatching.stdout, [])
    }

    func testRunFilterByAppBundleId() async {
        TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        let matching = await parseCommand("list-windows --monitor all --app-bundle-id bobko.AeroSpace.test-app --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(matching.exitCode.rawValue, 0)
        assertEquals(matching.stdout, ["1"])

        let mismatching = await parseCommand("list-windows --monitor all --app-bundle-id com.unknown.app --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(mismatching.exitCode.rawValue, 0)
        assertEquals(mismatching.stdout, [])
    }
}
