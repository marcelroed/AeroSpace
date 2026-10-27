@testable import AppBundle
import AppKit
import Combine
import Common
import XCTest

@MainActor
final class TrayMenuModelTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testUpdateTrayText_mainMode() {
        Workspace.get(byName: "b").rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0)
        }
        Workspace.get(byName: "a").rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        updateTrayText()

        let model = TrayMenuModel.shared
        assertEquals(model.trayText, "a")
        assertEquals(model.trayItems, [
            TrayItem(type: .workspace, name: "a", isActive: true, hasFullscreenWindows: false),
        ])
        assertEquals(model.workspaces, [
            WorkspaceViewModel(name: "a", suffix: " - bobko.AeroSpace.test-app", isFocused: true, isEffectivelyEmpty: false, isVisible: true, hasFullscreenWindows: false),
            WorkspaceViewModel(name: "b", suffix: " - bobko.AeroSpace.test-app", isFocused: false, isEffectivelyEmpty: false, isVisible: false, hasFullscreenWindows: false),
            WorkspaceViewModel(name: "setUpWorkspacesForTests", suffix: "", isFocused: false, isEffectivelyEmpty: true, isVisible: false, hasFullscreenWindows: false),
        ])
    }

    func testUpdateTrayText_nonMainModeAndFullscreen() {
        activeMode = "service"
        defer { activeMode = mainModeId }
        Workspace.get(byName: "b").rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0).isFullscreen = true
        }
        Workspace.get(byName: "a").rootTilingContainer.apply {
            let window = TestWindow.new(id: 1, parent: $0)
            window.isFullscreen = true
            assertEquals(window.focusWindow(), true)
        }

        updateTrayText()

        let model = TrayMenuModel.shared
        assertEquals(model.trayText, "(S) [a]")
        assertEquals(model.trayItems, [
            TrayItem(type: .mode, name: "S", isActive: true, hasFullscreenWindows: false),
            TrayItem(type: .workspace, name: "a", isActive: true, hasFullscreenWindows: true),
        ])
        assertEquals(model.workspaces, [
            WorkspaceViewModel(name: "a", suffix: " - bobko.AeroSpace.test-app", isFocused: true, isEffectivelyEmpty: false, isVisible: true, hasFullscreenWindows: true),
            WorkspaceViewModel(name: "b", suffix: " - bobko.AeroSpace.test-app", isFocused: false, isEffectivelyEmpty: false, isVisible: false, hasFullscreenWindows: true),
            WorkspaceViewModel(name: "setUpWorkspacesForTests", suffix: "", isFocused: false, isEffectivelyEmpty: true, isVisible: false, hasFullscreenWindows: false),
        ])
    }

    func testUpdateTrayText_emptyFocusedWorkspace() {
        updateTrayText()

        let model = TrayMenuModel.shared
        assertEquals(model.trayText, "setUpWorkspacesForTests")
        assertEquals(model.trayItems, [
            TrayItem(type: .workspace, name: "setUpWorkspacesForTests", isActive: true, hasFullscreenWindows: false),
        ])
        assertEquals(model.workspaces, [
            WorkspaceViewModel(name: "setUpWorkspacesForTests", suffix: " - Test Monitor", isFocused: true, isEffectivelyEmpty: true, isVisible: true, hasFullscreenWindows: false),
        ])
    }

    func testUpdateTrayText_publishesOnlyChangedValues() {
        updateTrayText()
        var publishedChanges = 0
        let subscription = TrayMenuModel.shared.objectWillChange.sink { publishedChanges += 1 }
        defer { subscription.cancel() }

        updateTrayText()
        assertEquals(publishedChanges, 0)

        Workspace.get(byName: "a").rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }
        updateTrayText()
        assertEquals(publishedChanges, 3) // trayText, workspaces, trayItems
    }

    func testUpdateTrayText_publishesAppearanceChange() {
        let app = NSApplication.shared
        let prevAppearance = app.appearance
        defer {
            app.appearance = prevAppearance
            updateTrayText()
        }
        app.appearance = NSAppearance(named: .aqua)
        updateTrayText()
        assertEquals(TrayMenuModel.shared.appearanceTheme, .light)
        var publishedChanges = 0
        let subscription = TrayMenuModel.shared.objectWillChange.sink { publishedChanges += 1 }
        defer { subscription.cancel() }

        // The tray text stays the same, but the menu must still be rebuilt with the new appearance
        app.appearance = NSAppearance(named: .darkAqua)
        updateTrayText()
        assertEquals(TrayMenuModel.shared.appearanceTheme, .dark)
        assertEquals(publishedChanges, 1)
    }

    func testSystemImageName() {
        func imageName(_ name: String, _ type: TrayItemType = .workspace, isActive: Bool = false) -> String? {
            TrayItem(type: type, name: name, isActive: isActive, hasFullscreenWindows: false).systemImageName
        }
        assertEquals(imageName("0"), "0.square")
        assertEquals(imageName("50", isActive: true), "50.square.fill")
        assertEquals(imageName("05"), "05.square")
        assertEquals(imageName("00", .mode), "00.circle")
        assertEquals(imageName("51"), nil)
        assertEquals(imageName("-1"), nil)
        // Int() accepts these, but there are no such symbols
        assertEquals(imageName("+5"), nil)
        assertEquals(imageName("-0"), nil)
        assertEquals(imageName("005"), nil)
        assertEquals(imageName("050"), nil)
        assertEquals(imageName("A"), "a.square")
        assertEquals(imageName("Z", .mode), "z.circle")
        assertEquals(imageName("a"), nil)
        assertEquals(imageName("AB"), nil)
        assertEquals(imageName("1A"), nil)
        assertEquals(imageName("é"), nil)
    }

    func testSystemImageNameIsAnExistingSymbol() {
        let numbers = (0 ... 60).flatMap { [String($0), "0\($0)", "00\($0)", "+\($0)", "-\($0)"] }
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)
        for name in numbers + letters {
            for (type, isActive) in [(TrayItemType.mode, true), (.workspace, true), (.workspace, false)] {
                let item = TrayItem(type: type, name: name, isActive: isActive, hasFullscreenWindows: false)
                if let imageName = item.systemImageName, NSImage(systemSymbolName: imageName, accessibilityDescription: nil) == nil {
                    fail("Workspace '\(name)' maps to '\(imageName)', which isn't an SF Symbol")
                }
            }
        }
    }
}
