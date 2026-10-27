@testable import AppBundle
import Common
import Foundation
import Testing

@Suite(.aeroSpaceGlobalState)
struct FormatTest {
    @Test(arguments: [
        ("", .success([])),
        ("%{window-id} | %{tab}", .success([.interVar(.windowId), .literal(" | "), .interVar(.tab)])),
        // `%` without `{` is a literal
        ("id: %{window-id}%{newline}%%{app-name}%", .success([
            .literal("id: "), .interVar(.windowId), .interVar(.newline), .literal("%"), .interVar(.appName), .literal("%"),
        ])),
        ("%{foo} %{bar}", .failure("Can't parse 'foo'.\nPossible values: \(FormatVar.unionLiteral)")),
        ("%{window-id} %{foo", .failure("Unbalanced curly braces")),
    ] as [(String, Result<[FormatToken], CmdParseError>)])
    func parseFormat(raw: String, expected: Result<[FormatToken], CmdParseError>) {
        expectEqual(Result { () throws(CmdParseError) in try AppBundle.parseFormat(raw) }, expected)
    }

    @Test
    func resolveWindowPrefetchesTitleOnlyWhenNeeded() async {
        let window = TestWindow.new(id: 3, parent: focus.workspace.rootTilingContainerCreatingIfNeeded())

        let withTitle = await WindowWithPrefetchedTitle.resolveWindow(window, for: [.literal("foo"), .interVar(.windowTitle)])
        expectEqual(withTitle.title, "TestWindow(3)")

        let withoutTitle = await WindowWithPrefetchedTitle.resolveWindow(window, for: [.interVar(.windowId), .interVar(.newline)])
        expectEqual(withoutTitle.title, nil)
    }

    /// `windows`: the ids and titles of windows in the focused workspace
    @Test(arguments: [
        ([], [.interVar(.windowId)], []),
        ([(42, "")], [.interVar(.windowId), .interVar(.tab), .literal("X"), .interVar(.newline), .literal("end")], ["42\tX\nend"]),
        ([(2, "non-empty"), (1, "")], [.interVar(.windowTitle)], ["non-empty", ""]),
        // A column that ends with %{right-padding} is as wide as its widest cell. The last column isn't padded
        ([(3, "non-empty"), (10, "")], [.interVar(.windowId), .interVar(.rightPadding), .interVar(.windowTitle)], ["3 non-empty", "10"]),
        (
            [(2, "a"), (100, "bb")],
            [.interVar(.windowId), .interVar(.rightPadding), .literal(" | "), .interVar(.windowTitle), .interVar(.rightPadding), .literal(" END")],
            ["2   | a  END", "100 | bb END"],
        ),
    ] as [([(WindowId, String)], [FormatToken], [String])])
    func format(windows: [(WindowId, String)], format: [FormatToken], expected: [String]) async throws {
        var objs: [AeroObj] = []
        for (id, title) in windows {
            objs.append(await windowObj(id, title: title, for: format))
        }
        try expectEqual(objs.format(format), expected)
    }

    /// `windows`: ids of windows in the focused workspace. The expected JSON is compared without its layout
    @Test(arguments: [
        ([], [.interVar(.windowId)], "[]"),
        ([1, 2], [.interVar(.windowId)], #"[{"window-id":1},{"window-id":2}]"#),
        (
            [3],
            [.interVar(.windowId), .interVar(.windowTitle), .interVar(.windowIsFullscreen)],
            #"[{"window-id":3,"window-is-fullscreen":false,"window-title":"TestWindow(3)"}]"#,
        ),
        // The literals and %{right-padding} of a default format don't make keys
        ([7], [.literal("prefix"), .interVar(.windowId), .literal("  "), .interVar(.rightPadding)], #"[{"window-id":7}]"#),
        ([11], [.interVar(.windowId), .interVar(.newline), .interVar(.tab)], #"[{"newline":"\n","tab":"\t","window-id":11}]"#),
        ([5], [.interVar(.windowIsFullscreen), .literal(" "), .interVar(.windowIsFullscreen)], #"[{"window-is-fullscreen":false}]"#),
    ] as [([WindowId], [FormatToken], String)])
    func formatToJson(windows: [WindowId], format: [FormatToken], expected: String) async throws {
        var objs: [AeroObj] = []
        for id in windows {
            objs.append(await windowObj(id, title: "TestWindow(\(id))", for: format))
        }
        try expectEqual(compactJson(objs.formatToJson(format)), compactJson(expected))
    }

    @Test
    func formatFailsOnTheFirstUnavailableVariable() {
        // Each object fails with a different message: the possible values depend on the kind of the object
        let objs: [AeroObj] = [.workspace(focus.workspace), .monitor(testMonitor)]
        let format: [FormatToken] = [.interVar(.windowId), .interVar(.rightPadding), .interVar(.appName)]
        let expected = expanded(.windowId, objs[0])
        let lines = Result { () throws(FormatVarExpansionError) in try objs.format(format) }
        expectEqual(lines.failureOrNil?.description, expected, "lines")
        let json = Result { () throws(FormatVarExpansionError) in try objs.formatToJson(format) }
        expectEqual(json.failureOrNil?.description, expected, "json")
    }

    /// `tree` is workspace "a"; `expected` is the value with its type, or the error message
    @Test(arguments: expandRows)
    func expand(tree: String, obj: ExpandedObj, formatVar: FormatVar, expected: String) async {
        let workspace = setUpTree(tree, workspace: "a")
        let hadRoot = workspace.existingRootTilingContainer != nil
        expectEqual(expanded(formatVar, await obj.aeroObj(for: formatVar)), expected)
        expectEqual(workspace.existingRootTilingContainer != nil, hadRoot, "Expanding a variable doesn't create the root container")
    }

    @Test
    func everyVariableHasAnExpandRow() {
        let covered = Set(expandRows.map(\.2))
        expectEqual(FormatVar.allCases.filter { !covered.contains($0) }, [])
    }

    /// The error messages and `--format` list the variables that `subject.availableVars` lists: exactly those that expand
    @Test
    func variablesExpandOnTheObjectsThatListThem() async {
        let window = TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainerCreatingIfNeeded())
        let objs: [AeroObj] = [
            .window(await .resolveWindow(window, for: [.interVar(.windowTitle)])),
            .workspace(focus.workspace),
            .app(testApp),
            .monitor(testMonitor),
        ]
        for obj in objs {
            for formatVar in FormatVar.allCases where formatVar != .rightPadding {
                let result = Result { () throws(FormatVarExpansionError) in try formatVar.expand(obj) }
                let isUnavailable = if case .failure(.unavailable) = result { true } else { false }
                expectEqual(isUnavailable, !obj.subject.availableVars.contains(formatVar), "\(formatVar.rawValue) of \(obj.subject)")
            }
        }
    }

    /// The docs pages include the variables of their objects by tag
    @Test
    func docsListEveryVariableUnderTheTagOfItsObject() throws {
        let adoc = try String(contentsOf: projectRoot.appending(path: "docs/util/format-vars.adoc"), encoding: .utf8)
        var tag = ""
        var documented: [String: Set<String>] = [:]
        for line in adoc.split(separator: "\n") {
            if line.starts(with: "// tag::") {
                tag = String(line.dropFirst("// tag::".count).prefix { $0 != "[" })
            } else if line.starts(with: "%{") {
                documented[tag, default: []].insert(String(line.dropFirst(2).prefix { $0 != "}" }))
            }
        }
        let expected = Dictionary(grouping: FormatVar.allCases) { $0.subject.map { "\($0)" } ?? "formatting" }
            .mapValues { Set($0.map(\.rawValue)) }
        expectEqual(documented, expected)
    }
}

/// The object of an `expand` row. The windows are those of the row's tree
nonisolated enum ExpandedObj: Sendable {
    case window(WindowId)
    /// After `fullscreen`
    case fullscreenWindow(WindowId)
    /// Unbound while its title was read
    case closedWindow(WindowId)
    /// Workspace "a"
    case workspace
    case app
    case monitor

    @MainActor func aeroObj(for formatVar: FormatVar) async -> AeroObj {
        switch self {
            case .window(let id), .fullscreenWindow(let id), .closedWindow(let id):
                let window = Window.get(byId: id).orDie()
                if case .fullscreenWindow = self { window.isFullscreen = true }
                let resolved = await WindowWithPrefetchedTitle.resolveWindow(window, for: [.interVar(formatVar)])
                if case .closedWindow = self { window.unbindFromParent() }
                return .window(resolved)
            case .workspace: return .workspace(Workspace.get(byName: "a"))
            case .app: return .app(testApp)
            case .monitor: return .monitor(testMonitor)
        }
    }
}

/// Every variable has a row (`everyVariableHasAnExpandRow`), Raycast's included
nonisolated private let expandRows: [(String, ExpandedObj, FormatVar, String)] = [
    ("h_tiles(9)", .window(9), .windowId, "Int(9)"),
    ("h_tiles(1)", .window(1), .windowIsFullscreen, "Bool(false)"),
    ("h_tiles(1)", .fullscreenWindow(1), .windowIsFullscreen, "Bool(true)"),
    ("h_tiles(1)", .window(1), .windowTitle, "String(TestWindow(1))"),
    ("h_tiles(1)", .window(1), .windowLayout, "String(h_tiles)"),
    ("v_tiles(1)", .window(1), .windowLayout, "String(v_tiles)"),
    ("h_accordion(1)", .window(1), .windowLayout, "String(h_accordion)"),
    ("v_accordion(1)", .window(1), .windowLayout, "String(v_accordion)"),
    ("h_tiles(2 v_accordion(1))", .window(1), .windowParentContainerLayout, "String(v_accordion)"),
    ("floating(1)", .window(1), .windowLayout, "String(floating)"),
    ("macos_fullscreen(1)", .window(1), .windowLayout, "String(macos_native_fullscreen)"),
    ("macos_hidden(1)", .window(1), .windowLayout, "String(macos_native_window_of_hidden_app)"),
    ("macos_minimized(1)", .window(1), .windowLayout, "String(macos_native_minimized)"),
    ("macos_popup(1)", .window(1), .windowLayout, "String(NULL-WINDOW-LAYOUT)"),
    ("h_tiles(1)", .closedWindow(1), .windowLayout, "NULL-PARENT"),

    ("h_tiles(1)", .workspace, .workspace, "String(a)"),
    ("h_tiles(1)", .window(1), .workspace, "String(a)"),
    ("macos_minimized(1)", .window(1), .workspace, "String(NULL-WORKSPACE)"),
    ("h_tiles(*1)", .workspace, .workspaceIsFocused, "Bool(true)"),
    ("h_tiles(1)", .workspace, .workspaceIsFocused, "Bool(false)"),
    ("h_tiles(*1)", .window(1), .workspaceIsVisible, "Bool(true)"),
    ("h_tiles(1)", .workspace, .workspaceIsVisible, "Bool(false)"),
    ("v_accordion(1)", .workspace, .workspaceRootContainerLayout, "String(v_accordion)"),
    ("floating(1)", .workspace, .workspaceRootContainerLayout, "String(h_tiles)"), // The config's, without a root container

    ("h_tiles(1)", .app, .appBundleId, "String(bobko.AeroSpace.test-app)"),
    ("h_tiles(1)", .window(1), .appName, "String(bobko.AeroSpace.test-app)"),
    ("h_tiles(1)", .app, .appPid, "Int(0)"),
    ("h_tiles(1)", .app, .appExecPath, "String(NULL-APP-EXEC-PATH)"),
    ("h_tiles(1)", .window(1), .appBundlePath, "String(NULL-APP-BUNDLE-PATH)"),

    ("h_tiles(1)", .monitor, .monitorId, "Int(1)"),
    ("h_tiles(1)", .monitor, .monitorAppKitNsScreenScreensId, "Int(1)"),
    ("h_tiles(1)", .monitor, .monitorName, "String(Test Monitor)"),
    ("h_tiles(1)", .window(1), .monitorName, "String(Test Monitor)"),
    ("macos_minimized(1)", .window(1), .monitorName, "String(NULL-MONITOR)"),
    ("h_tiles(1)", .workspace, .monitorIsMain, "Bool(true)"),

    ("h_tiles(1)", .window(1), .newline, "String(\n)"),
    ("h_tiles(1)", .monitor, .tab, "String(\t)"),
    ("h_tiles(1)", .window(1), .rightPadding, "'right-padding' interpolation variable cannot be expanded"),
]

/// The value of `formatVar` for `obj` with its type, `Int(5)`, or the error message
private func expanded(_ formatVar: FormatVar, _ obj: AeroObj) -> String {
    do {
        let primitive = try formatVar.expand(obj)
        return "\(primitive.kind.rawValue)(\(primitive.toString()))"
    } catch {
        return error.description
    }
}

/// Window `id` of the test app with `title`, in the focused workspace, its title read as `format` needs
private func windowObj(_ id: WindowId, title: String, for format: [FormatToken]) async -> AeroObj {
    let window = TestWindow.new(id: id, parent: focus.workspace.rootTilingContainerCreatingIfNeeded())
    fake.windows[id] = FakeWindow(app: testApp, rect: nil, title: title)
    return .window(await .resolveWindow(window, for: format))
}
