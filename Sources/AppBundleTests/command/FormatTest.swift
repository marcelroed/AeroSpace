@testable import AppBundle
import Common
import Foundation
import Testing

/// The value of `formatVar` for `obj` with its kind, `Int(5)`, or the error message
private func expanded(_ formatVar: FormatVar, _ obj: AeroObj) -> String {
    do {
        let primitive = try formatVar.expand(obj)
        return "\(primitive.kind.rawValue)(\(primitive.toString()))"
    } catch {
        return error.description
    }
}

private let workspaceName = "a"

/// A new window with `id` in `parent` (the root container of workspace `a` by default), as an AeroObj
private func newWindowObj(id: UInt32, parent: Container? = nil, title: String? = nil) -> AeroObj {
    .window(.forTest(window: TestWindow.new(id: id, parent: parent ?? Workspace.get(byName: workspaceName).rootTilingContainer), title: title))
}

/// The JSON encoding of `expected`
private func json(_ expected: [[String: Primitive]]) -> String { JSONEncoder.aeroSpaceDefault.encodeToString(expected).orDie() }

@Suite(.aeroSpaceGlobalState)
struct FormatTest {
    @Test
    func aeroObjSubject() {
        let window = TestWindow.new(id: 1, parent: Workspace.get(byName: workspaceName).rootTilingContainer)
        #expect(AeroObj.window(.forTest(window: window, title: nil)).subject == .window)
        #expect(AeroObj.workspace(Workspace.get(byName: workspaceName)).subject == .workspace)
        #expect(AeroObj.app(TestApp.shared).subject == .app)
        #expect(AeroObj.monitor(mainMonitorInfo).subject == .monitor)
    }

    @Test
    func resolveWindowPrefetchesTitleOnlyWhenNeeded() async throws {
        let window = TestWindow.new(id: 3, parent: Workspace.get(byName: workspaceName).rootTilingContainer)

        let withTitle = try await WindowWithPrefetchedTitle.resolveWindow(window, for: [.literal("foo"), .interVar(.windowTitle)], .nonCancellable)
        #expect(withTitle.title == "TestWindow(3)")

        let withoutTitle = try await WindowWithPrefetchedTitle.resolveWindow(window, for: [.interVar(.windowId), .interVar(.newline)], .nonCancellable)
        #expect(withoutTitle.title == nil)
    }

    @Test
    func parseFormat() throws {
        #expect(try AppBundle.parseFormat("%{window-id} | %{tab}") == [.interVar(.windowId), .literal(" | "), .interVar(.tab)])
        #expect(throws: CmdParseError.invalid("Can't parse 'bogus'.\nPossible values: \(FormatVar.unionLiteral)")) {
            try AppBundle.parseFormat("%{bogus}")
        }
    }

    @Test
    func formatEmptyInput() throws {
        let objs: [AeroObj] = []
        #expect(try objs.format([.interVar(.windowId)]) == [])
    }

    @Test
    func formatWithNewlineAndTab() throws {
        let objs = [newWindowObj(id: 42)]
        let result = try objs.format([.interVar(.windowId), .interVar(.tab), .literal("X"), .interVar(.newline), .literal("end")])
        #expect(result == ["42\tX\nend"])
    }

    @Test
    func formatMultipleRightPaddingColumns() throws {
        let windows = [newWindowObj(id: 2, title: "a"), newWindowObj(id: 100, title: "bb")]
        let result = try windows.format([
            .interVar(.windowId),
            .interVar(.rightPadding),
            .literal(" | "),
            .interVar(.windowTitle),
            .interVar(.rightPadding),
            .literal(" END"),
        ])
        #expect(result == ["2   | a  END", "100 | bb END"])
    }

    @Test
    func formatFailsOnTheFirstUnavailableVariable() {
        let objs: [AeroObj] = [.workspace(Workspace.get(byName: workspaceName))]
        do {
            _ = try objs.format([.interVar(.windowId), .interVar(.rightPadding), .interVar(.windowTitle)])
            Issue.record("Expected a failure")
        } catch {
            #expect(error.description == expanded(.windowId, objs[0]))
        }
    }

    @Test
    func primitive() throws {
        #expect(Primitive.bool(true).kind == .bool)
        #expect(Primitive.int(7).kind == .int)
        #expect(Primitive.string("x").kind == .string)

        #expect(Primitive.bool(true).toString() == "true")
        #expect(Primitive.bool(false).toString() == "false")
        #expect(Primitive.int(42).toString() == "42")
        #expect(Primitive.string("hello").toString() == "hello")

        #expect(Primitive.int(UInt32(5)).toString() == "5")
        #expect(Primitive.int(Int32(-3)).toString() == "-3")
        #expect(Primitive.int(Int(123)).toString() == "123")

        for (primitive, expected) in [(Primitive.bool(true), "true"), (.bool(false), "false"), (.int(42), "42"), (.string("hi"), "\"hi\"")] {
            #expect(String(data: try JSONEncoder().encode(primitive), encoding: .utf8) == expected)
        }

        #expect(Primitive.Kind.bool.rawValue == "Bool")
        #expect(Primitive.Kind.int.rawValue == "Int")
        #expect(Primitive.Kind.string.rawValue == "String")
    }

    @Test
    func expandWindowIdAndIsFullscreen() {
        let window = TestWindow.new(id: 9, parent: Workspace.get(byName: workspaceName).rootTilingContainer)
        window.isFullscreen = true
        let obj = AeroObj.window(.forTest(window: window, title: "title-x"))
        #expect(expanded(.windowId, obj) == "Int(9)")
        #expect(expanded(.windowIsFullscreen, obj) == "Bool(true)")
        #expect(expanded(.windowTitle, obj) == "String(title-x)")
    }

    @Test
    func expandWindowLayoutTiling() {
        let root = Workspace.get(byName: workspaceName).rootTilingContainer
        let obj = newWindowObj(id: 1, parent: root)

        root.layout = .tiles
        root.changeOrientation(.h)
        #expect(expanded(.windowLayout, obj) == "String(h_tiles)")
        #expect(expanded(.windowParentContainerLayout, obj) == "String(h_tiles)")

        root.layout = .accordion
        #expect(expanded(.windowLayout, obj) == "String(h_accordion)")

        root.changeOrientation(.v)
        #expect(expanded(.windowLayout, obj) == "String(v_accordion)")

        root.layout = .tiles
        #expect(expanded(.windowLayout, obj) == "String(v_tiles)")
    }

    @Test
    func expandWindowLayoutOfTheOtherPlacements() {
        let workspace = Workspace.get(byName: workspaceName)
        #expect(expanded(.windowLayout, newWindowObj(id: 1, parent: workspace.floatingWindowsContainer)) == "String(floating)")
        #expect(expanded(.windowLayout, newWindowObj(id: 2, parent: workspace.macOsNativeFullscreenWindowsContainer)) == "String(macos_native_fullscreen)")
        #expect(expanded(.windowLayout, newWindowObj(id: 3, parent: workspace.macOsNativeHiddenAppsWindowsContainer)) == "String(macos_native_window_of_hidden_app)")
        #expect(expanded(.windowLayout, newWindowObj(id: 4, parent: macosMinimizedWindowsContainer)) == "String(macos_native_minimized)")
        #expect(expanded(.windowLayout, newWindowObj(id: 5, parent: macosPopupWindowsContainer)) == "String(NULL-WINDOW-LAYOUT)")
    }

    @Test
    func expandWindowToWorkspaceAndMonitor() {
        let obj = newWindowObj(id: 1)
        #expect(expanded(.workspace, obj) == "String(\(workspaceName))")
        #expect(expanded(.monitorName, obj) == "String(\(mainMonitorInfo.name))")
    }

    @Test
    func expandDetachedWindowToWorkspaceAndMonitor() {
        let window = TestWindow.new(id: 1, parent: Workspace.get(byName: workspaceName).rootTilingContainer)
        window.unbindFromParent()
        let obj = AeroObj.window(.forTest(window: window, title: nil))
        #expect(expanded(.workspace, obj) == "String(NULL-WORKSPACE)")
        #expect(expanded(.monitorName, obj) == "String(NULL-MONITOR)")
        #expect(expanded(.windowLayout, obj) == "NULL-PARENT")
    }

    @Test
    func expandWindowToApp() {
        let obj = newWindowObj(id: 1)
        #expect(expanded(.appPid, obj) == "Int(0)")
        #expect(expanded(.appBundleId, obj) == "String(bobko.AeroSpace.test-app)")
    }

    @Test
    func expandWorkspaceVars() {
        let workspace = Workspace.get(byName: workspaceName)
        #expect(workspace.focusWorkspace())
        let obj = AeroObj.workspace(workspace)
        #expect(expanded(.workspace, obj) == "String(\(workspaceName))")
        #expect(expanded(.workspaceIsFocused, obj) == "Bool(true)")
        #expect(expanded(.workspaceIsVisible, obj) == "Bool(true)")
        #expect(expanded(.workspaceRootContainerLayout, obj) == "String(h_tiles)")
    }

    @Test
    func expandingTheRootContainerLayoutDoesntCreateTheRoot() {
        let workspace = setUpTree("floating(1)", workspace: workspaceName)
        #expect(expanded(.workspaceRootContainerLayout, .workspace(workspace)) == "String(h_tiles)") // The config's default
        #expect(workspace.existingRootTilingContainer == nil)
        workspace.rootTilingContainer.layout = .accordion
        #expect(expanded(.workspaceRootContainerLayout, .workspace(workspace)) == "String(h_accordion)")
    }

    @Test
    func expandWorkspaceFocusedAndVisibleForOtherWorkspace() {
        let obj = AeroObj.workspace(Workspace.get(byName: "other"))
        #expect(expanded(.workspaceIsFocused, obj) == "Bool(false)")
        #expect(expanded(.workspaceIsVisible, obj) == "Bool(false)")
    }

    @Test
    func expandWorkspaceToMonitor() {
        let obj = AeroObj.workspace(Workspace.get(byName: workspaceName))
        #expect(expanded(.monitorName, obj) == "String(\(mainMonitorInfo.name))")
        #expect(expanded(.monitorIsMain, obj) == "Bool(true)")
    }

    @Test
    func expandMonitorVars() {
        let monitor = mainMonitorInfo
        let obj = AeroObj.monitor(monitor)
        #expect(expanded(.monitorAppKitNsScreenScreensId, obj) == "Int(\(monitor.monitorAppKitNsScreenScreensId))")
        #expect(expanded(.monitorName, obj) == "String(\(monitor.name))")
        #expect(expanded(.monitorIsMain, obj) == "Bool(true)")
        #expect(expanded(.monitorId, obj) == "Int(1)")
    }

    @Test
    func expandAppVars() {
        let obj = AeroObj.app(TestApp.shared)
        #expect(expanded(.appBundleId, obj) == "String(bobko.AeroSpace.test-app)")
        #expect(expanded(.appName, obj) == "String(bobko.AeroSpace.test-app)")
        #expect(expanded(.appPid, obj) == "Int(0)")
        #expect(expanded(.appExecPath, obj) == "String(NULL-APP-EXEC-PATH)")
        #expect(expanded(.appBundlePath, obj) == "String(NULL-APP-BUNDLE-PATH)")
    }

    @Test
    func expandFormattingVars() {
        let obj = newWindowObj(id: 5)
        #expect(expanded(.newline, obj) == "String(\n)")
        #expect(expanded(.tab, obj) == "String(\t)")
        #expect(expanded(.rightPadding, obj) == "'right-padding' interpolation variable cannot be expanded")
    }

    @Test
    func unavailableVariableMessage() {
        let msg = expanded(.windowId, .workspace(Workspace.get(byName: workspaceName)))
        #expect(msg.starts(with: "Unknown interpolation variable 'window-id'. Possible values:"))
        // A workspace has the workspace and monitor variables, and the formatting ones
        #expect(msg.contains("\n  workspace\n"))
        #expect(msg.contains("monitor-name"))
        #expect(msg.contains("right-padding"))
        #expect(!msg.contains("app-name"))
    }

    @Test
    func unavailableVariableMessageListsPossibleValues() {
        #expect(
            expanded(.windowId, .monitor(mainMonitorInfo)) ==
                "Unknown interpolation variable 'window-id'. Possible values:\n" +
                "  monitor-id\n  monitor-appkit-nsscreen-screens-id\n  monitor-name\n  monitor-is-main\n" +
                "  right-padding\n  newline\n  tab",
        )
    }

    @Test
    func formatToJson() throws {
        let objs: [AeroObj] = []
        #expect(try objs.formatToJson([.interVar(.windowId)]) == json([]))

        let window = TestWindow.new(id: 42, parent: Workspace.get(byName: workspaceName).rootTilingContainer)
        window.isFullscreen = true
        #expect(
            try [AeroObj.window(.forTest(window: window, title: "hello"))]
                .formatToJson([.interVar(.windowId), .interVar(.windowTitle), .interVar(.windowIsFullscreen)]) ==
                json([["window-id": .int(42), "window-title": .string("hello"), "window-is-fullscreen": .bool(true)]]),
        )

        #expect(try [newWindowObj(id: 1), newWindowObj(id: 2)].formatToJson([.interVar(.windowId)]) == json([["window-id": .int(1)], ["window-id": .int(2)]]))
    }

    @Test
    func formatToJsonSkipsLiteralsAndRightPadding() throws {
        let objs = [newWindowObj(id: 7)]
        #expect(try objs.formatToJson([.literal("ignored-prefix"), .interVar(.windowId), .literal("  "), .interVar(.rightPadding)]) == json([["window-id": .int(7)]]))
    }

    @Test
    func formatToJsonExpandsFormattingVars() throws {
        let objs = [newWindowObj(id: 11)]
        #expect(
            try objs.formatToJson([.interVar(.windowId), .interVar(.newline), .interVar(.tab)]) ==
                json([["window-id": .int(11), "newline": .string("\n"), "tab": .string("\t")]]),
        )
    }

    @Test
    func formatToJsonFailsOnTheFirstObject() {
        // Both objects fail, but with different messages: the possible values depend on the object kind
        let objs: [AeroObj] = [.workspace(Workspace.get(byName: workspaceName)), .monitor(mainMonitorInfo)]
        do {
            _ = try objs.formatToJson([.interVar(.windowId)])
            Issue.record("Expected a failure")
        } catch {
            #expect(error.description == expanded(.windowId, objs[0]))
        }
    }

    // The same variable always has the same value, so it's impossible to tell whether the first or the last one is kept
    @Test
    func formatToJsonRepeatedVariableIsOutputOnce() throws {
        let objs = [newWindowObj(id: 5)]
        #expect(
            try objs.formatToJson([.interVar(.windowIsFullscreen), .literal(" between literals "), .interVar(.windowIsFullscreen)]) ==
                json([["window-is-fullscreen": .bool(false)]]),
        )
    }
}
