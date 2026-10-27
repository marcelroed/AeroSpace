@testable import AppBundle
import Common
import Foundation
import XCTest

private func assertPrimitive(_ actual: Result<Primitive, InterVarExpansionError>, _ expected: Primitive, fileID: String = #fileID, filePath: StaticString = #filePath, line: Int = #line, column: Int = #column) {
    switch actual {
        case .failure: failExpectedActual("Result.success(\(expected.toString()))", actual, fileID: fileID, filePath: filePath, line: line, column: column)
        case .success(let primitive):
            if primitive.kind != expected.kind || primitive.toString() != expected.toString() {
                failExpectedActual("\(expected.kind.rawValue)(\(expected.toString()))", "\(primitive.kind.rawValue)(\(primitive.toString()))", fileID: fileID, filePath: filePath, line: line, column: column)
            }
    }
}

nonisolated final class FormatTest: XCTestCase {} // XCTestCase's initializers are nonisolated

@MainActor
extension FormatTest {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testAeroObjKind() {
        let window = TestWindow.new(id: 1, parent: Workspace.get(byName: name).rootTilingContainer)
        let workspace = Workspace.get(byName: name)
        assertEquals(AeroObj.window(.forTest(window: window, title: nil)).kind, .window)
        assertEquals(AeroObj.workspace(workspace).kind, .workspace)
        assertEquals(AeroObj.app(TestApp.shared).kind, .app)
        assertEquals(AeroObj.monitor(mainMonitorInfo).kind, .monitor)
    }

    func testResolveWindowForFormatVarPrefetchesTitleOnlyWhenNeeded() async throws {
        let window = TestWindow.new(id: 7, parent: Workspace.get(byName: name).rootTilingContainer)
        let withTitle = try await WindowWithPrefetchedTitle.resolveWindow(window, for: .window(.windowTitle), .nonCancellable)
        assertEquals(withTitle.title, "TestWindow(7)")

        let withoutTitle = try await WindowWithPrefetchedTitle.resolveWindow(window, for: .window(.windowId), .nonCancellable)
        assertNil(withoutTitle.title)
    }

    func testResolveWindowForFormatTokensPrefetchesTitleOnlyWhenNeeded() async throws {
        let window = TestWindow.new(id: 3, parent: Workspace.get(byName: name).rootTilingContainer)

        let withTitle = try await WindowWithPrefetchedTitle.resolveWindow(window, for: [
            .literal("foo"),
            .interVar(.formatVar(.window(.windowTitle))),
        ], .nonCancellable)
        assertEquals(withTitle.title, "TestWindow(3)")

        let withoutTitle = try await WindowWithPrefetchedTitle.resolveWindow(window, for: [
            .interVar(.formatVar(.window(.windowId))),
            .interVar(.plainInterVar(.newline)),
        ], .nonCancellable)
        assertNil(withoutTitle.title)
    }

    func testFormatEmptyInput() {
        let result: [AeroObj] = []
        assertSucc(result.format([.interVar(.formatVar(.window(.windowId)))]), [])
    }

    func testFormatWithNewlineAndTab() {
        let objs = [newWindowObj(id: 42)]
        let result = objs.format([
            .interVar(.formatVar(.window(.windowId))),
            .interVar(.plainInterVar(.tab)),
            .literal("X"),
            .interVar(.plainInterVar(.newline)),
            .literal("end"),
        ])
        assertSucc(result, ["42\tX\nend"])
    }

    func testFormatMultipleRightPaddingColumns() {
        let windows = [newWindowObj(id: 2, title: "a"), newWindowObj(id: 100, title: "bb")]
        let result = windows.format([
            .interVar(.formatVar(.window(.windowId))),
            .interVar(.plainInterVar(.rightPadding)),
            .literal(" | "),
            .interVar(.formatVar(.window(.windowTitle))),
            .interVar(.plainInterVar(.rightPadding)),
            .literal(" END"),
        ])
        assertSucc(result, [
            "2   | a  END",
            "100 | bb END",
        ])
    }

    func testFormatFailureAccumulatesErrors() {
        let workspace = Workspace.get(byName: name)
        let objs: [AeroObj] = [.workspace(workspace)]
        let result = objs.format([
            .interVar(.formatVar(.window(.windowId))),
            .interVar(.plainInterVar(.rightPadding)),
            .interVar(.formatVar(.window(.windowTitle))),
        ])
        let msg = result.failureOrNil?.map(\.description).joined(separator: "\n")
        assertNotNil(msg)
        assertTrue(msg?.contains("Unknown interpolation variable 'window-id'") == true)
        assertTrue(msg?.contains("Unknown interpolation variable 'window-title'") == true)
    }

    func testPrimitiveKind() {
        assertEquals(Primitive.bool(true).kind, .bool)
        assertEquals(Primitive.int(7).kind, .int)
        assertEquals(Primitive.string("x").kind, .string)
    }

    func testPrimitiveToString() {
        assertEquals(Primitive.bool(true).toString(), "true")
        assertEquals(Primitive.bool(false).toString(), "false")
        assertEquals(Primitive.int(42).toString(), "42")
        assertEquals(Primitive.string("hello").toString(), "hello")
    }

    func testPrimitiveIntConvenienceConstructors() {
        assertEquals(Primitive.int(UInt32(5)).toString(), "5")
        assertEquals(Primitive.int(Int32(-3)).toString(), "-3")
        assertEquals(Primitive.int(Int(123)).toString(), "123")
    }

    func testPrimitiveEncoding() throws {
        let cases: [(Primitive, String)] = [
            (.bool(true), "true"),
            (.bool(false), "false"),
            (.int(42), "42"),
            (.string("hi"), "\"hi\""),
        ]
        for (primitive, expected) in cases {
            let data = try JSONEncoder().encode(primitive)
            assertEquals(String(data: data, encoding: .utf8), expected)
        }
    }

    func testPrimitiveKindRawValues() {
        assertEquals(Primitive.Kind.bool.rawValue, "Bool")
        assertEquals(Primitive.Kind.int.rawValue, "Int")
        assertEquals(Primitive.Kind.string.rawValue, "String")
    }

    func testExpandWindowIdAndIsFullscreen() {
        let window = TestWindow.new(id: 9, parent: Workspace.get(byName: name).rootTilingContainer)
        window.isFullscreen = true
        let obj = AeroObj.window(.forTest(window: window, title: "title-x"))

        assertPrimitive(FormatVar.window(.windowId).expandFormatVar(obj: obj), .int(Int64(9)))
        assertPrimitive(FormatVar.window(.windowIsFullscreen).expandFormatVar(obj: obj), .bool(true))
        assertPrimitive(FormatVar.window(.windowTitle).expandFormatVar(obj: obj), .string("title-x"))
    }

    func testExpandWindowLayoutTiling() {
        let root = Workspace.get(byName: name).rootTilingContainer
        let obj = newWindowObj(id: 1, parent: root)

        root.layout = .tiles
        root.changeOrientation(.h)
        assertPrimitive(FormatVar.window(.windowLayout).expandFormatVar(obj: obj), .string("h_tiles"))
        assertPrimitive(FormatVar.window(.windowParentContainerLayout).expandFormatVar(obj: obj), .string("h_tiles"))

        root.layout = .accordion
        assertPrimitive(FormatVar.window(.windowLayout).expandFormatVar(obj: obj), .string("h_accordion"))

        root.changeOrientation(.v)
        assertPrimitive(FormatVar.window(.windowLayout).expandFormatVar(obj: obj), .string("v_accordion"))

        root.layout = .tiles
        assertPrimitive(FormatVar.window(.windowLayout).expandFormatVar(obj: obj), .string("v_tiles"))
    }

    func testExpandWindowLayoutFloating() {
        let obj = newWindowObj(id: 1, parent: Workspace.get(byName: name).floatingWindowsContainer)
        assertPrimitive(FormatVar.window(.windowLayout).expandFormatVar(obj: obj), .string("floating"))
    }

    func testExpandWindowLayoutMacosNativeFullscreen() {
        let obj = newWindowObj(id: 1, parent: Workspace.get(byName: name).macOsNativeFullscreenWindowsContainer)
        assertPrimitive(FormatVar.window(.windowLayout).expandFormatVar(obj: obj), .string("macos_native_fullscreen"))
    }

    func testExpandWindowLayoutMacosNativeHiddenApp() {
        let obj = newWindowObj(id: 1, parent: Workspace.get(byName: name).macOsNativeHiddenAppsWindowsContainer)
        assertPrimitive(FormatVar.window(.windowLayout).expandFormatVar(obj: obj), .string("macos_native_window_of_hidden_app"))
    }

    func testExpandWindowLayoutMacosNativeMinimized() {
        let obj = newWindowObj(id: 1, parent: macosMinimizedWindowsContainer)
        assertPrimitive(FormatVar.window(.windowLayout).expandFormatVar(obj: obj), .string("macos_native_minimized"))
    }

    func testExpandWindowLayoutMacosPopup() {
        let obj = newWindowObj(id: 1, parent: macosPopupWindowsContainer)
        assertPrimitive(FormatVar.window(.windowLayout).expandFormatVar(obj: obj), .string("NULL-WINDOW-LAYOUT"))
    }

    func testExpandWindowToWorkspaceWhenWindowHasWorkspace() {
        let obj = newWindowObj(id: 1)
        assertPrimitive(FormatVar.workspace(.workspaceName).expandFormatVar(obj: obj), .string(name))
    }

    func testExpandWindowToWorkspaceWhenWindowDetached() {
        let window = TestWindow.new(id: 1, parent: Workspace.get(byName: name).rootTilingContainer)
        window.unbindFromParent()
        let obj = AeroObj.window(.forTest(window: window, title: nil))
        assertPrimitive(FormatVar.workspace(.workspaceName).expandFormatVar(obj: obj), .string("NULL-WORKSPACE"))
    }

    func testExpandWindowToMonitorWhenWindowHasMonitor() {
        let obj = newWindowObj(id: 1)
        assertPrimitive(FormatVar.monitor(.monitorName).expandFormatVar(obj: obj), .string(mainMonitorInfo.name))
    }

    func testExpandWindowToMonitorWhenWindowDetached() {
        let window = TestWindow.new(id: 1, parent: Workspace.get(byName: name).rootTilingContainer)
        window.unbindFromParent()
        let obj = AeroObj.window(.forTest(window: window, title: nil))
        assertPrimitive(FormatVar.monitor(.monitorName).expandFormatVar(obj: obj), .string("NULL-MONITOR"))
    }

    func testExpandWindowToApp() {
        let obj = newWindowObj(id: 1)
        assertPrimitive(FormatVar.app(.appPid).expandFormatVar(obj: obj), .int(Int64(0)))
        assertPrimitive(FormatVar.app(.appBundleId).expandFormatVar(obj: obj), .string("bobko.AeroSpace.test-app"))
    }

    func testExpandWorkspaceVars() {
        let workspace = Workspace.get(byName: name)
        assertTrue(workspace.focusWorkspace())
        let obj = AeroObj.workspace(workspace)
        assertPrimitive(FormatVar.workspace(.workspaceName).expandFormatVar(obj: obj), .string(name))
        assertPrimitive(FormatVar.workspace(.workspaceFocused).expandFormatVar(obj: obj), .bool(true))
        assertPrimitive(FormatVar.workspace(.workspaceVisible).expandFormatVar(obj: obj), .bool(true))
        assertPrimitive(FormatVar.workspace(.workspaceRootContainerLayout).expandFormatVar(obj: obj), .string("h_tiles"))
    }

    func testExpandWorkspaceFocusedAndVisibleForOtherWorkspace() {
        let other = Workspace.get(byName: "other")
        let obj = AeroObj.workspace(other)
        assertPrimitive(FormatVar.workspace(.workspaceFocused).expandFormatVar(obj: obj), .bool(false))
        assertPrimitive(FormatVar.workspace(.workspaceVisible).expandFormatVar(obj: obj), .bool(false))
    }

    func testExpandWorkspaceToMonitor() {
        let workspace = Workspace.get(byName: name)
        let obj = AeroObj.workspace(workspace)
        assertPrimitive(FormatVar.monitor(.monitorName).expandFormatVar(obj: obj), .string(mainMonitorInfo.name))
        assertPrimitive(FormatVar.monitor(.monitorIsMain).expandFormatVar(obj: obj), .bool(true))
    }

    func testExpandMonitorVars() {
        let monitor = mainMonitorInfo
        let obj = AeroObj.monitor(monitor)
        assertPrimitive(FormatVar.monitor(.monitorAppKitNsScreenScreensId).expandFormatVar(obj: obj), .int(Int64(monitor.monitorAppKitNsScreenScreensId)))
        assertPrimitive(FormatVar.monitor(.monitorName).expandFormatVar(obj: obj), .string(monitor.name))
        assertPrimitive(FormatVar.monitor(.monitorIsMain).expandFormatVar(obj: obj), .bool(true))
        assertPrimitive(FormatVar.monitor(.monitorId_oneBased).expandFormatVar(obj: obj), .int(Int64(1)))
    }

    func testExpandAppVars() {
        let obj = AeroObj.app(TestApp.shared)
        assertPrimitive(FormatVar.app(.appBundleId).expandFormatVar(obj: obj), .string("bobko.AeroSpace.test-app"))
        assertPrimitive(FormatVar.app(.appName).expandFormatVar(obj: obj), .string("bobko.AeroSpace.test-app"))
        assertPrimitive(FormatVar.app(.appPid).expandFormatVar(obj: obj), .int(Int64(0)))
        assertPrimitive(FormatVar.app(.appExecPath).expandFormatVar(obj: obj), .string("NULL-APP-EXEC-PATH"))
        assertPrimitive(FormatVar.app(.appBundlePath).expandFormatVar(obj: obj), .string("NULL-APP-BUNDLE-PATH"))
    }

    func testPlainInterVarExpand() {
        assertPrimitive(PlainInterVar.newline.expandFormatVar(), .string("\n"))
        assertPrimitive(PlainInterVar.tab.expandFormatVar(), .string("\t"))
    }

    func testInterVarExpandDelegates() {
        let obj = newWindowObj(id: 5)

        assertPrimitive(InterVar.formatVar(.window(.windowId)).expandFormatVar(obj: obj), .int(Int64(5)))
        assertPrimitive(InterVar.plainInterVar(.newline).expandFormatVar(obj: obj), .string("\n"))
    }

    func testUnknownInterpolationVariableMessage() {
        let workspace = AeroObj.workspace(Workspace.get(byName: name))
        let msg = unknownInterpolationVariable(variable: "bogus", workspace)
        assertTrue(msg.starts(with: "Unknown interpolation variable 'bogus'."))
        assertTrue(msg.contains("Possible values:"))
        // Workspace kind should include workspace + monitor vars + plain inter vars.
        assertTrue(msg.contains("\n  workspace\n"))
        assertTrue(msg.contains("monitor-name"))
        assertTrue(msg.contains("right-padding"))
    }

    func testUnknownInterpolationVariableMessageListsPossibleValues() {
        assertEquals(
            unknownInterpolationVariable(variable: "bogus", .monitor(mainMonitorInfo)),
            "Unknown interpolation variable 'bogus'. Possible values:\n" +
                "  monitor-id\n  monitor-appkit-nsscreen-screens-id\n  monitor-name\n  monitor-is-main\n" +
                "  right-padding\n  newline\n  tab",
        )
    }

    func testFormatToJsonEmptyInput() {
        assertFormatToJson([], [.interVar(.formatVar(.window(.windowId)))], [])
    }

    func testFormatToJsonSingleObject() {
        let window = TestWindow.new(id: 42, parent: Workspace.get(byName: name).rootTilingContainer)
        window.isFullscreen = true
        assertFormatToJson(
            [.window(.forTest(window: window, title: "hello"))],
            [
                .interVar(.formatVar(.window(.windowId))),
                .interVar(.formatVar(.window(.windowTitle))),
                .interVar(.formatVar(.window(.windowIsFullscreen))),
            ],
            [["window-id": Primitive.int(42), "window-title": Primitive.string("hello"), "window-is-fullscreen": Primitive.bool(true)]],
        )
    }

    func testFormatToJsonMultipleObjects() {
        assertFormatToJson(
            [newWindowObj(id: 1), newWindowObj(id: 2)],
            [.interVar(.formatVar(.window(.windowId)))],
            [["window-id": Primitive.int(1)], ["window-id": Primitive.int(2)]],
        )
    }

    func testFormatToJsonIgnoresLiterals() {
        assertFormatToJson(
            [newWindowObj(id: 7)],
            [.literal("ignored-prefix"), .interVar(.formatVar(.window(.windowId))), .literal("  ")],
            [["window-id": Primitive.int(7)]],
        )
    }

    func testFormatToJsonIgnoresRightPaddingWhenFlagTrue() {
        assertFormatToJson(
            [newWindowObj(id: 8)],
            [.interVar(.formatVar(.window(.windowId))), .interVar(.plainInterVar(.rightPadding))],
            [["window-id": Primitive.int(8)]],
            ignoreRightPaddingVar: true,
        )
    }

    func testFormatToJsonRightPaddingFailsWhenFlagFalse() {
        let objs = [newWindowObj(id: 8)]
        let result = objs.formatToJson(
            [
                .interVar(.formatVar(.window(.windowId))),
                .interVar(.plainInterVar(.rightPadding)),
            ],
            ignoreRightPaddingVar: false,
        )
        assertFail(result, "'right-padding' interpolation variable cannot be expanded")
    }

    func testFormatToJsonExpandsPlainInterVars() {
        assertFormatToJson(
            [newWindowObj(id: 11)],
            [.interVar(.formatVar(.window(.windowId))), .interVar(.plainInterVar(.newline)), .interVar(.plainInterVar(.tab))],
            [["window-id": Primitive.int(11), "newline": Primitive.string("\n"), "tab": Primitive.string("\t")]],
        )
    }

    func testFormatToJsonFailsOnUnknownInterpolationVariable() {
        let objs: [AeroObj] = [.workspace(Workspace.get(byName: name))]
        let result = objs.formatToJson(
            [.interVar(.formatVar(.window(.windowId)))],
            ignoreRightPaddingVar: true,
        )
        assertFail(result)
        assertTrue(result.failureOrNil?.starts(with: "Unknown interpolation variable 'window-id'.") == true)
    }

    func testFormatToJsonReturnsFirstFailureForMultipleObjects() {
        // Both objects fail, but with different messages: the possible values depend on the object kind
        let objs: [AeroObj] = [
            .workspace(Workspace.get(byName: name)),
            .monitor(mainMonitorInfo),
        ]
        let result = objs.formatToJson(
            [.interVar(.formatVar(.window(.windowId)))],
            ignoreRightPaddingVar: true,
        )
        assertFail(result, unknownInterpolationVariable(variable: "window-id", objs[0]))
    }

    // The same variable always has the same value, so it's impossible to tell whether the first or the last one is kept
    func testFormatToJsonRepeatedVariableIsOutputOnce() {
        let window = TestWindow.new(id: 5, parent: Workspace.get(byName: name).rootTilingContainer)
        window.isFullscreen = false
        assertFormatToJson(
            [.window(.forTest(window: window, title: nil))],
            [
                .interVar(.formatVar(.window(.windowIsFullscreen))),
                .literal(" between literals "),
                .interVar(.formatVar(.window(.windowIsFullscreen))),
            ],
            [["window-is-fullscreen": Primitive.bool(false)]],
        )
    }

    /// A new window with `id` in `parent` (the root container of the test workspace by default), as an AeroObj
    private func newWindowObj(id: UInt32, parent: NonLeafTreeNodeObject? = nil, title: String? = nil) -> AeroObj {
        .window(.forTest(window: TestWindow.new(id: id, parent: parent ?? Workspace.get(byName: name).rootTilingContainer), title: title))
    }

    /// Checks that `objects` format to the JSON encoding of `expected`
    private func assertFormatToJson(
        _ objects: [AeroObj],
        _ format: [InterToken<InterVar>],
        _ expected: [[String: Primitive]],
        ignoreRightPaddingVar: Bool = true,
        fileID: String = #fileID,
        filePath: StaticString = #filePath,
        line: Int = #line,
        column: Int = #column,
    ) {
        let result = objects.formatToJson(format, ignoreRightPaddingVar: ignoreRightPaddingVar)
        assertSucc(result, JSONEncoder.aeroSpaceDefault.encodeToString(expected).orDie(), fileID: fileID, filePath: filePath, line: line, column: column)
    }
}
