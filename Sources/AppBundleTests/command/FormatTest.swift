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
private func newWindowObj(id: WindowId, parent: Container? = nil, title: String? = nil) -> AeroObj {
    .window(.forTest(window: TestWindow.new(id: id, parent: parent ?? Workspace.get(byName: workspaceName).rootTilingContainerCreatingIfNeeded()), title: title))
}

/// The JSON encoding of `expected`
private func json(_ expected: [[String: Primitive]]) -> String { JSONEncoder.aeroSpaceDefault.encodeToString(expected).orDie() }

@Suite(.aeroSpaceGlobalState)
struct FormatTest {
    @Test
    func aeroObjSubject() {
        let window = TestWindow.new(id: 1, parent: Workspace.get(byName: workspaceName).rootTilingContainerCreatingIfNeeded())
        expectEqual(AeroObj.window(.forTest(window: window, title: nil)).subject, .window)
        expectEqual(AeroObj.workspace(Workspace.get(byName: workspaceName)).subject, .workspace)
        expectEqual(AeroObj.app(TestApp.shared).subject, .app)
        expectEqual(AeroObj.monitor(testMonitor).subject, .monitor)
    }

    @Test
    func resolveWindowPrefetchesTitleOnlyWhenNeeded() async throws {
        let window = TestWindow.new(id: 3, parent: Workspace.get(byName: workspaceName).rootTilingContainerCreatingIfNeeded())

        let withTitle = try await WindowWithPrefetchedTitle.resolveWindow(window, for: [.literal("foo"), .interVar(.windowTitle)], .nonCancellable)
        expectEqual(withTitle.title, "TestWindow(3)")

        let withoutTitle = try await WindowWithPrefetchedTitle.resolveWindow(window, for: [.interVar(.windowId), .interVar(.newline)], .nonCancellable)
        expectEqual(withoutTitle.title, nil)
    }

    @Test
    func parseFormat() throws {
        try expectEqual(AppBundle.parseFormat("%{window-id} | %{tab}"), [.interVar(.windowId), .literal(" | "), .interVar(.tab)])
        #expect(throws: CmdParseError.invalid("Can't parse 'bogus'.\nPossible values: \(FormatVar.unionLiteral)")) {
            try AppBundle.parseFormat("%{bogus}")
        }
    }

    @Test
    func formatEmptyInput() throws {
        let objs: [AeroObj] = []
        try expectEqual(objs.format([.interVar(.windowId)]), [])
    }

    @Test
    func formatWithNewlineAndTab() throws {
        let objs = [newWindowObj(id: 42)]
        let result = try objs.format([.interVar(.windowId), .interVar(.tab), .literal("X"), .interVar(.newline), .literal("end")])
        expectEqual(result, ["42\tX\nend"])
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
        expectEqual(result, ["2   | a  END", "100 | bb END"])
    }

    @Test
    func formatFailsOnTheFirstUnavailableVariable() {
        let objs: [AeroObj] = [.workspace(Workspace.get(byName: workspaceName))]
        do {
            _ = try objs.format([.interVar(.windowId), .interVar(.rightPadding), .interVar(.windowTitle)])
            Issue.record("Expected a failure")
        } catch {
            expectEqual(error.description, expanded(.windowId, objs[0]))
        }
    }

    @Test
    func primitive() throws {
        expectEqual(Primitive.bool(true).kind, .bool)
        expectEqual(Primitive.int(7).kind, .int)
        expectEqual(Primitive.string("x").kind, .string)

        expectEqual(Primitive.bool(true).toString(), "true")
        expectEqual(Primitive.bool(false).toString(), "false")
        expectEqual(Primitive.int(42).toString(), "42")
        expectEqual(Primitive.string("hello").toString(), "hello")

        expectEqual(Primitive.int(UInt32(5)).toString(), "5")
        expectEqual(Primitive.int(Int32(-3)).toString(), "-3")
        expectEqual(Primitive.int(Int(123)).toString(), "123")

        for (primitive, expected) in [(Primitive.bool(true), "true"), (.bool(false), "false"), (.int(42), "42"), (.string("hi"), "\"hi\"")] {
            expectEqual(String(data: try JSONEncoder().encode(primitive), encoding: .utf8), expected)
        }

        expectEqual(Primitive.Kind.bool.rawValue, "Bool")
        expectEqual(Primitive.Kind.int.rawValue, "Int")
        expectEqual(Primitive.Kind.string.rawValue, "String")
    }

    @Test
    func expandWindowIdAndIsFullscreen() {
        let window = TestWindow.new(id: 9, parent: Workspace.get(byName: workspaceName).rootTilingContainerCreatingIfNeeded())
        window.isFullscreen = true
        let obj = AeroObj.window(.forTest(window: window, title: "title-x"))
        expectEqual(expanded(.windowId, obj), "Int(9)")
        expectEqual(expanded(.windowIsFullscreen, obj), "Bool(true)")
        expectEqual(expanded(.windowTitle, obj), "String(title-x)")
    }

    @Test
    func expandWindowLayoutTiling() {
        let root = Workspace.get(byName: workspaceName).rootTilingContainerCreatingIfNeeded()
        let obj = newWindowObj(id: 1, parent: root)

        root.layout = .tiles
        root.changeOrientation(.h)
        expectEqual(expanded(.windowLayout, obj), "String(h_tiles)")
        expectEqual(expanded(.windowParentContainerLayout, obj), "String(h_tiles)")

        root.layout = .accordion
        expectEqual(expanded(.windowLayout, obj), "String(h_accordion)")

        root.changeOrientation(.v)
        expectEqual(expanded(.windowLayout, obj), "String(v_accordion)")

        root.layout = .tiles
        expectEqual(expanded(.windowLayout, obj), "String(v_tiles)")
    }

    @Test
    func expandWindowLayoutOfTheOtherPlacements() {
        let workspace = Workspace.get(byName: workspaceName)
        expectEqual(expanded(.windowLayout, newWindowObj(id: 1, parent: workspace.containerCreatingIfNeeded(.floating))), "String(floating)")
        expectEqual(expanded(.windowLayout, newWindowObj(id: 2, parent: workspace.containerCreatingIfNeeded(.macosFullscreen))), "String(macos_native_fullscreen)")
        expectEqual(expanded(.windowLayout, newWindowObj(id: 3, parent: workspace.containerCreatingIfNeeded(.macosHiddenApp))), "String(macos_native_window_of_hidden_app)")
        expectEqual(expanded(.windowLayout, newWindowObj(id: 4, parent: macosMinimizedWindowsContainer)), "String(macos_native_minimized)")
        expectEqual(expanded(.windowLayout, newWindowObj(id: 5, parent: macosPopupWindowsContainer)), "String(NULL-WINDOW-LAYOUT)")
    }

    @Test
    func expandWindowToWorkspaceAndMonitor() {
        let obj = newWindowObj(id: 1)
        expectEqual(expanded(.workspace, obj), "String(\(workspaceName))")
        expectEqual(expanded(.monitorName, obj), "String(\(testMonitor.name))")
    }

    @Test
    func expandDetachedWindowToWorkspaceAndMonitor() {
        let window = TestWindow.new(id: 1, parent: Workspace.get(byName: workspaceName).rootTilingContainerCreatingIfNeeded())
        window.unbindFromParent()
        let obj = AeroObj.window(.forTest(window: window, title: nil))
        expectEqual(expanded(.workspace, obj), "String(NULL-WORKSPACE)")
        expectEqual(expanded(.monitorName, obj), "String(NULL-MONITOR)")
        expectEqual(expanded(.windowLayout, obj), "NULL-PARENT")
    }

    @Test
    func expandWindowToApp() {
        let obj = newWindowObj(id: 1)
        expectEqual(expanded(.appPid, obj), "Int(0)")
        expectEqual(expanded(.appBundleId, obj), "String(bobko.AeroSpace.test-app)")
    }

    @Test
    func expandWorkspaceVars() {
        let workspace = Workspace.get(byName: workspaceName)
        #expect(workspace.focusWorkspace())
        let obj = AeroObj.workspace(workspace)
        expectEqual(expanded(.workspace, obj), "String(\(workspaceName))")
        expectEqual(expanded(.workspaceIsFocused, obj), "Bool(true)")
        expectEqual(expanded(.workspaceIsVisible, obj), "Bool(true)")
        expectEqual(expanded(.workspaceRootContainerLayout, obj), "String(h_tiles)")
    }

    @Test
    func expandingTheRootContainerLayoutDoesntCreateTheRoot() {
        let workspace = setUpTree("floating(1)", workspace: workspaceName)
        expectEqual(expanded(.workspaceRootContainerLayout, .workspace(workspace)), "String(h_tiles)") // The config's default
        expectEqual(workspace.existingRootTilingContainer, nil)
        workspace.rootTilingContainerCreatingIfNeeded().layout = .accordion
        expectEqual(expanded(.workspaceRootContainerLayout, .workspace(workspace)), "String(h_accordion)")
    }

    @Test
    func expandWorkspaceFocusedAndVisibleForOtherWorkspace() {
        let obj = AeroObj.workspace(Workspace.get(byName: "other"))
        expectEqual(expanded(.workspaceIsFocused, obj), "Bool(false)")
        expectEqual(expanded(.workspaceIsVisible, obj), "Bool(false)")
    }

    @Test
    func expandWorkspaceToMonitor() {
        let obj = AeroObj.workspace(Workspace.get(byName: workspaceName))
        expectEqual(expanded(.monitorName, obj), "String(\(testMonitor.name))")
        expectEqual(expanded(.monitorIsMain, obj), "Bool(true)")
    }

    @Test
    func expandMonitorVars() {
        let monitor = testMonitor
        let obj = AeroObj.monitor(monitor)
        expectEqual(expanded(.monitorAppKitNsScreenScreensId, obj), "Int(\(monitor.monitorAppKitNsScreenScreensId))")
        expectEqual(expanded(.monitorName, obj), "String(\(monitor.name))")
        expectEqual(expanded(.monitorIsMain, obj), "Bool(true)")
        expectEqual(expanded(.monitorId, obj), "Int(1)")
    }

    @Test
    func expandAppVars() {
        let obj = AeroObj.app(TestApp.shared)
        expectEqual(expanded(.appBundleId, obj), "String(bobko.AeroSpace.test-app)")
        expectEqual(expanded(.appName, obj), "String(bobko.AeroSpace.test-app)")
        expectEqual(expanded(.appPid, obj), "Int(0)")
        expectEqual(expanded(.appExecPath, obj), "String(NULL-APP-EXEC-PATH)")
        expectEqual(expanded(.appBundlePath, obj), "String(NULL-APP-BUNDLE-PATH)")
    }

    @Test
    func expandFormattingVars() {
        let obj = newWindowObj(id: 5)
        expectEqual(expanded(.newline, obj), "String(\n)")
        expectEqual(expanded(.tab, obj), "String(\t)")
        expectEqual(expanded(.rightPadding, obj), "'right-padding' interpolation variable cannot be expanded")
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
        expectEqual(
            expanded(.windowId, .monitor(testMonitor)),
            "Unknown interpolation variable 'window-id'. Possible values:\n" +
                "  monitor-id\n  monitor-appkit-nsscreen-screens-id\n  monitor-name\n  monitor-is-main\n" +
                "  right-padding\n  newline\n  tab",
        )
    }

    @Test
    func formatToJson() throws {
        let objs: [AeroObj] = []
        try expectEqual(objs.formatToJson([.interVar(.windowId)]), json([]))

        let window = TestWindow.new(id: 42, parent: Workspace.get(byName: workspaceName).rootTilingContainerCreatingIfNeeded())
        window.isFullscreen = true
        try expectEqual(
            [AeroObj.window(.forTest(window: window, title: "hello"))]
                .formatToJson([.interVar(.windowId), .interVar(.windowTitle), .interVar(.windowIsFullscreen)]),
            json([["window-id": .int(42), "window-title": .string("hello"), "window-is-fullscreen": .bool(true)]]),
        )

        try expectEqual([newWindowObj(id: 1), newWindowObj(id: 2)].formatToJson([.interVar(.windowId)]), json([["window-id": .int(1)], ["window-id": .int(2)]]))
    }

    @Test
    func formatToJsonSkipsLiteralsAndRightPadding() throws {
        let objs = [newWindowObj(id: 7)]
        try expectEqual(objs.formatToJson([.literal("ignored-prefix"), .interVar(.windowId), .literal("  "), .interVar(.rightPadding)]), json([["window-id": .int(7)]]))
    }

    @Test
    func formatToJsonExpandsFormattingVars() throws {
        let objs = [newWindowObj(id: 11)]
        try expectEqual(
            objs.formatToJson([.interVar(.windowId), .interVar(.newline), .interVar(.tab)]),
            json([["window-id": .int(11), "newline": .string("\n"), "tab": .string("\t")]]),
        )
    }

    @Test
    func formatToJsonFailsOnTheFirstObject() {
        // Both objects fail, but with different messages: the possible values depend on the object kind
        let objs: [AeroObj] = [.workspace(Workspace.get(byName: workspaceName)), .monitor(testMonitor)]
        do {
            _ = try objs.formatToJson([.interVar(.windowId)])
            Issue.record("Expected a failure")
        } catch {
            expectEqual(error.description, expanded(.windowId, objs[0]))
        }
    }

    // The same variable always has the same value, so it's impossible to tell whether the first or the last one is kept
    @Test
    func formatToJsonRepeatedVariableIsOutputOnce() throws {
        let objs = [newWindowObj(id: 5)]
        try expectEqual(
            objs.formatToJson([.interVar(.windowIsFullscreen), .literal(" between literals "), .interVar(.windowIsFullscreen)]),
            json([["window-is-fullscreen": .bool(false)]]),
        )
    }
}
