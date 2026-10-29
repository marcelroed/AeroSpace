@testable import AppBundle
import Common
import Foundation
import Testing

// The rows run on the world of `setUpTwoMonitors`. A `--json` row compares its JSON through `compactJson`. The rows
// with Raycast's commands (the AeroSpace Raycast extension) keep the output that the extension reads

@Suite(.aeroSpaceGlobalState)
struct ListCommandsTest {
    @Test(arguments: listWindowsRows)
    func listWindows(command: String, expected: CmdOutput) async { await expectOutput(command, expected) }

    @Test(arguments: listWorkspacesRows)
    func listWorkspaces(command: String, expected: CmdOutput) async { await expectOutput(command, expected) }

    @Test(arguments: listMonitorsRows)
    func listMonitors(command: String, expected: CmdOutput) async { await expectOutput(command, expected) }

    @Test(arguments: listAppsRows)
    func listApps(command: String, expected: CmdOutput) async { await expectOutput(command, expected) }

    @Test(arguments: listModesRows)
    func listModes(command: String, expected: CmdOutput) async { await expectOutput(command, expected) }

    private func expectOutput(_ command: String, _ expected: CmdOutput) async {
        setUpTwoMonitors()
        let isJson = command.contains("--json")
        expectEqual(compactingJson(await runCmd(command), isJson), compactingJson(expected, isJson), "\(command)")
    }

    @Test
    func jsonIsPrettyPrintedWithSortedKeysAndUnescapedSlashes() async {
        fake.apps = [otherApp]
        let output = await runCmd("list-apps --json --format '%{app-name} %{app-bundle-path}'")
        expectEqual(output, CmdOutput(stdout: [
            """
            [
              {
                "app-bundle-path" : "/Applications/Other.app",
                "app-name" : "Other"
              }
            ]
            """,
        ]))
    }

    @Test
    func listWindowsFocusedFailsWithoutAFocusedWindow() async {
        expectEqual(await runCmd("list-windows --focused"), .fail(noWindowIsFocused))
    }

    @Test
    func listWindowsAll_windowsOfTheSameAppAndTitleAreOrderedByWorkspace() async {
        // The title isn't fetched for this format, so all the windows tie on the app name and the title. The windows
        // are collected from a Set of workspaces, whose order is random, and ten of them make it fail reliably (RB-13).
        // The IDs go down while the workspaces go up (in logical order: w2 < w10), so ordering by ID fails too
        for index: UInt32 in (1 ... 10).reversed() {
            setUpTree("h_tiles(\(11 - index))", workspace: "w\(index)")
        }
        let output = await runCmd("list-windows --all --format '%{window-id}'")
        expectEqual(output, CmdOutput(stdout: (1 ... 10).reversed().map { String($0) }))
    }

    @Test
    func listWindowsWorkspace_windowsOfTheSameAppAndTitleAreInTreeOrder() async {
        // Tree order differs from ID order. Within one workspace, tied windows are listed in tree order (RB-13)
        setUpTree("h_tiles(3 v_tiles(1) 2)", workspace: "a")
        let output = await runCmd("list-windows --workspace a --format '%{window-id}'")
        expectEqual(output, CmdOutput(stdout: ["3", "1", "2"]))
    }

    @Test
    func listWorkspacesAll_namesThatDifferOnlyInLeadingZerosAreOrderedByName() async {
        #expect(Workspace.get(byName: "01") < Workspace.get(byName: "1"))
        #expect(!(Workspace.get(byName: "1") < Workspace.get(byName: "01")))
        setUpTree("h_tiles(1)", workspace: "1")
        setUpTree("h_tiles(2)", workspace: "01")
        setUpTree("h_tiles(3)", workspace: "001")
        let output = await runCmd("list-workspaces --all")
        expectEqual(output, CmdOutput(stdout: ["001", "01", "1", "setUpWorkspacesForTests"]))
    }

    @Test
    func listExecEnvVarsIsSortedByName() async {
        // Ten variables, so that the dictionary order can't match the sorted order by chance (RB-13)
        let names = ["PATH", "HOME", "LANG", "A", "Z", "B", "Y", "C", "X", "FOO"]
        world.config.execConfig.envVariables = Dictionary(uniqueKeysWithValues: names.map { ($0, "value-\($0)") })

        let output = await runCmd("list-exec-env-vars")
        expectEqual(output, CmdOutput(stdout: names.sorted().map { "\($0)=value-\($0)" }))
    }
}

/// An app with a bundle path, which macOS hides
private let otherApp = AppInfo(pid: 1, bundleId: "test.other", name: "Other", execPath: nil, bundlePath: "/Applications/Other.app")

/// - The left monitor shows workspace a, `h_tiles(*1 2)`: it's focused
/// - The right monitor shows workspace b, `v_accordion(3)`. Window 3 is "Other window" of `otherApp`. The mouse is there
/// - Workspace c, `h_tiles(4)`, is invisible. Workspace d is empty and persistent
/// - The modes are main, resize and service, and resize is active
private func setUpTwoMonitors() {
    fake.monitorInfos = [testMonitor, rightTestMonitor]
    fake.apps = [testApp, otherApp]
    fake.hiddenApps = [otherApp.pid]
    fake.mouseLocation = CGPoint(x: 2500, y: 500)
    updateMonitors()
    let b = Workspace.get(byName: "b")
    check(testMonitor.setActiveWorkspace(Workspace.get(byName: "a")) && rightTestMonitor.setActiveWorkspace(b))
    setUpTree("h_tiles(*1 2)", workspace: "a")
    setUpTree("v_accordion()", workspace: "b")
    fake.windows[3] = FakeWindow(app: otherApp, rect: nil, title: "Other window")
    _ = Window(id: 3, otherApp, parent: b.rootTilingContainerCreatingIfNeeded(), weight: 1, index: nil)
    setUpTree("h_tiles(4)", workspace: "c")
    world.config.persistentWorkspaces = ["d"]
    Workspace.garbageCollectUnusedWorkspaces()
    world.config.modes = ["main": Mode(bindings: [:]), "service": Mode(bindings: [:]), "resize": Mode(bindings: [:])]
    world.activeMode = "resize"
}

/// `output` with its stdout compacted, if it's JSON
private func compactingJson(_ output: CmdOutput, _ isJson: Bool) -> CmdOutput {
    guard isJson else { return output }
    var result = output
    result.stdout = output.stdout.map(compactJson)
    return result
}

nonisolated private let raycastWindowFormat = "%{app-name} %{window-title} %{window-id} %{workspace} %{app-bundle-id} %{app-bundle-path} " +
    "%{monitor-name} %{workspace-is-focused} %{workspace-is-visible} %{window-layout} %{window-is-fullscreen}"
nonisolated private let raycastWorkspaceFormat = "%{workspace} %{workspace-is-focused} %{workspace-is-visible} %{monitor-name} " +
    "%{workspace-root-container-layout}"

/// Windows are sorted by app name ("Other" < "bobko..."), then by title. Without the title in the format, windows of an
/// app keep workspace order, then tree order
nonisolated private let listWindowsRows: [(String, CmdOutput)] = [
    ("list-windows --all", CmdOutput(stdout: [
        "3 | Other                    | Other window",
        "1 | bobko.AeroSpace.test-app | TestWindow(1)",
        "2 | bobko.AeroSpace.test-app | TestWindow(2)",
        "4 | bobko.AeroSpace.test-app | TestWindow(4)",
    ])),
    ("list-windows --all --count", CmdOutput(stdout: ["4"])),
    ("list-windows --all --format %{window-title}", CmdOutput(stdout: ["Other window", "TestWindow(1)", "TestWindow(2)", "TestWindow(4)"])),
    ("list-windows --focused --format %{window-id}", CmdOutput(stdout: ["1"])),
    ("list-windows --workspace c a --format %{window-id}", CmdOutput(stdout: ["1", "2", "4"])),
    ("list-windows --workspace focused --format %{window-id}", CmdOutput(stdout: ["1", "2"])),
    ("list-windows --workspace visible --format %{window-id}", CmdOutput(stdout: ["3", "1", "2"])),
    ("list-windows --workspace d --format %{window-id}", .ok),
    ("list-windows --monitor mouse --workspace visible --format %{window-id}", CmdOutput(stdout: ["3"])),
    ("list-windows --monitor focused --workspace visible --format %{window-id}", CmdOutput(stdout: ["1", "2"])),
    ("list-windows --monitor 2 --format %{window-id}", CmdOutput(stdout: ["3"])),
    ("list-windows --monitor 3 --format %{window-id}", .fail("Invalid monitor ID: 3")),
    ("list-windows --monitor all --pid 1 --format %{window-id}", CmdOutput(stdout: ["3"])),
    ("list-windows --monitor all --pid 9999 --format %{window-id}", .ok),
    ("list-windows --monitor all --app-bundle-id bobko.AeroSpace.test-app --format %{window-id}", CmdOutput(stdout: ["1", "2", "4"])),
    ("list-windows --all --json --format %{window-id}", CmdOutput(stdout: [#"[{"window-id":3},{"window-id":1},{"window-id":2},{"window-id":4}]"#])),
    // Raycast. It also lists all windows with `--all`
    ("list-windows --workspace b --json --format '\(raycastWindowFormat)'", CmdOutput(stdout: [#"""
    [{"app-bundle-id": "test.other", "app-bundle-path": "/Applications/Other.app", "app-name": "Other",
      "monitor-name": "Right Monitor", "window-id": 3, "window-is-fullscreen": false, "window-layout": "v_accordion",
      "window-title": "Other window", "workspace": "b", "workspace-is-focused": false, "workspace-is-visible": true}]
    """#])),

    ("list-windows --pid 1", .fail("Mandatory option is not specified (--focused|--all|--monitor|--workspace)")),
    ("list-windows --pid 1 --focused", .fail("--focused conflicts with other \"filtering\" flags")),
    ("list-windows --pid 1 --all", .fail("--all conflicts with \"filtering\" flags. Please use '--monitor all' instead of '--all' alias")),
    ("list-windows --all --workspace a", .fail("Conflicting options: --all, --workspace")),
    ("list-windows --all --focused --monitor mouse", .fail("Conflicting options: --all, --focused")),
    ("list-windows --all --focused --monitor mouse --workspace focused", .fail("Conflicting options: --all, --focused, --workspace")),
    ("list-windows --workspace", .fail("<workspace>... is mandatory. <workspace> possible values: (<workspace-name>|focused|visible)")),
    ("list-windows --monitor 0", .fail("Monitor IDs use 1-based indexing. Values less than 1 are illegal")),
    ("list-windows --monitor left", .fail("Can't parse monitor ID 'left'. <monitor> possible values: (<monitor-id>|focused|mouse|all)")),
    ("list-windows --all --count --format %{window-title}", .fail("Conflicting options: --count, --format")),
    ("list-windows --all --count --json", .fail("Conflicting options: --count, --json")),
    ("list-windows --all --format '%{right-padding}' --json", .fail("%{right-padding} interpolation variable is not allowed when --json is used")),
    ("list-windows --all --format '%{window-title} |' --json", .fail("Only interpolation variables and spaces are allowed in '--format' when '--json' is used")),
]

/// Workspaces are sorted by name. The invisible workspaces c and d are on the main monitor
nonisolated private let listWorkspacesRows: [(String, CmdOutput)] = [
    ("list-workspaces --all", CmdOutput(stdout: ["a", "b", "c", "d"])),
    ("list-workspaces --all --count", CmdOutput(stdout: ["4"])),
    ("list-workspaces --focused", CmdOutput(stdout: ["a"])), // Raycast
    ("list-workspaces --monitor all --visible", CmdOutput(stdout: ["a", "b"])),
    ("list-workspaces --monitor all --visible no", CmdOutput(stdout: ["c", "d"])),
    ("list-workspaces --monitor all --empty", CmdOutput(stdout: ["d"])),
    ("list-workspaces --monitor all --empty no", CmdOutput(stdout: ["a", "b", "c"])),
    ("list-workspaces --monitor focused", CmdOutput(stdout: ["a", "c", "d"])),
    ("list-workspaces --monitor mouse", CmdOutput(stdout: ["b"])),
    ("list-workspaces --monitor 2 1 --visible", CmdOutput(stdout: ["a", "b"])),
    ("list-workspaces --monitor 3", .fail("Invalid monitor ID: 3")),
    ("list-workspaces --all --format '%{workspace}%{tab}%{monitor-id}'", CmdOutput(stdout: ["a\t1", "b\t2", "c\t1", "d\t1"])),
    // Raycast
    ("list-workspaces --all --json --format '\(raycastWorkspaceFormat)'", CmdOutput(stdout: [#"""
    [{"workspace": "a", "workspace-is-focused": true, "workspace-is-visible": true, "monitor-name": "Test Monitor",
      "workspace-root-container-layout": "h_tiles"},
     {"workspace": "b", "workspace-is-focused": false, "workspace-is-visible": true, "monitor-name": "Right Monitor",
      "workspace-root-container-layout": "v_accordion"},
     {"workspace": "c", "workspace-is-focused": false, "workspace-is-visible": false, "monitor-name": "Test Monitor",
      "workspace-root-container-layout": "h_tiles"},
     {"workspace": "d", "workspace-is-focused": false, "workspace-is-visible": false, "monitor-name": "Test Monitor",
      "workspace-root-container-layout": "h_tiles"}]
    """#])),

    ("list-workspaces --empty", .fail("Mandatory option is not specified (--all|--focused|--monitor)")),
    ("list-workspaces --visible", .fail("Mandatory option is not specified (--all|--focused|--monitor)")),
    ("list-workspaces --all --visible", .fail("--all conflicts with any other \"filtering\" options")),
    ("list-workspaces --focused --empty", .fail("--focused conflicts with all other \"filtering\" options")),
    ("list-workspaces --focused --all", .fail("Conflicting options: --all, --focused")),
    ("list-workspaces --focused --monitor 2", .fail("Conflicting options: --focused, --monitor")),
    ("list-workspaces --all --focused --monitor mouse", .fail("Conflicting options: --all, --focused, --monitor")),
    ("list-workspaces --all --format %{foo}", .fail("Failed to parse <output-format>. Can't parse 'foo'.\nPossible values: \(FormatVar.unionLiteral)")),
]

nonisolated private let listMonitorsRows: [(String, CmdOutput)] = [
    ("list-monitors", CmdOutput(stdout: ["1 | Test Monitor", "2 | Right Monitor"])),
    ("list-monitors --count", CmdOutput(stdout: ["2"])),
    ("list-monitors --focused", CmdOutput(stdout: ["1 | Test Monitor"])),
    ("list-monitors --focused no", CmdOutput(stdout: ["2 | Right Monitor"])),
    ("list-monitors --mouse", CmdOutput(stdout: ["2 | Right Monitor"])),
    ("list-monitors --mouse no --focused", CmdOutput(stdout: ["1 | Test Monitor"])),
    ("list-monitors --mouse --focused", .ok),
    ("list-monitors --format '%{monitor-appkit-nsscreen-screens-id} %{monitor-is-main}'", CmdOutput(stdout: ["1 true", "2 false"])),
    ("list-monitors --json", CmdOutput(stdout: [#"[{"monitor-id": 1, "monitor-name": "Test Monitor"}, {"monitor-id": 2, "monitor-name": "Right Monitor"}]"#])),
    // Raycast
    ("list-monitors --json --format '%{monitor-name} %{monitor-is-main}'", CmdOutput(stdout: [
        #"[{"monitor-name": "Test Monitor", "monitor-is-main": true}, {"monitor-name": "Right Monitor", "monitor-is-main": false}]"#,
    ])),
    ("list-monitors --format %{window-id}", .fail("Unknown interpolation variable 'window-id'. Possible values:\n" + monitorVars)),

    ("list-monitors --format", .fail("<output-format> is mandatory. Possible values:\n" + monitorVars)),
]

/// The variables of a monitor, one per line
nonisolated private let monitorVars: String = FormatVar.allCases
    .filter { $0.rawValue.starts(with: "monitor-") || $0.subject == nil }
    .map { "  " + $0.rawValue }
    .joined(separator: "\n")

/// Apps are sorted by name, then by pid. `otherApp` is hidden
nonisolated private let listAppsRows: [(String, CmdOutput)] = [
    ("list-apps", CmdOutput(stdout: [
        "1 | test.other               | Other",
        "0 | bobko.AeroSpace.test-app | bobko.AeroSpace.test-app",
    ])),
    ("list-apps --count", CmdOutput(stdout: ["2"])),
    ("list-apps --macos-native-hidden --format %{app-name}", CmdOutput(stdout: ["Other"])),
    ("list-apps --macos-native-hidden no --format %{app-bundle-id}", CmdOutput(stdout: ["bobko.AeroSpace.test-app"])),
    ("list-apps --json --format '%{app-pid} %{app-exec-path} %{app-bundle-path}'", CmdOutput(stdout: [#"""
    [{"app-pid": 1, "app-exec-path": "NULL-APP-EXEC-PATH", "app-bundle-path": "/Applications/Other.app"},
     {"app-pid": 0, "app-exec-path": "NULL-APP-EXEC-PATH", "app-bundle-path": "NULL-APP-BUNDLE-PATH"}]
    """#])),
]

nonisolated private let listModesRows: [(String, CmdOutput)] = [
    ("list-modes", CmdOutput(stdout: ["main", "resize", "service"])),
    ("list-modes --count", CmdOutput(stdout: ["3"])),
    ("list-modes --current", CmdOutput(stdout: ["resize"])), // Raycast
    ("list-modes --json", CmdOutput(stdout: [#"[{"mode-id": "main"}, {"mode-id": "resize"}, {"mode-id": "service"}]"#])),
    ("list-modes --current --json", CmdOutput(stdout: [#"[{"mode-id": "resize"}]"#])),

    ("list-modes --json --count", .fail("Conflicting options: --count, --json")),
    ("list-modes --current --count", .fail("Conflicting options: --count, --current")),
]
