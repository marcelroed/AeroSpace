@testable import AppBundle
import AppKit
import Common
import Observation
import Synchronization
import Testing

@Suite(.aeroSpaceGlobalState)
struct TrayMenuModelTest {
    @Test
    func testUpdateTrayText_mainMode() {
        setUpTree("h_tiles(2)", workspace: "b")
        setUpTree("h_tiles(*1)", workspace: "a")

        updateTrayText()

        let model = TrayMenuModel.shared
        #expect(model.trayText == "a")
        #expect(model.trayItems == [
            TrayItem(type: .workspace, name: "a", isActive: true, hasFullscreenWindows: false),
        ])
        #expect(model.workspaces == [
            WorkspaceViewModel(name: "a", suffix: " - bobko.AeroSpace.test-app", isFocused: true, isEffectivelyEmpty: false, isVisible: true, hasFullscreenWindows: false),
            WorkspaceViewModel(name: "b", suffix: " - bobko.AeroSpace.test-app", isFocused: false, isEffectivelyEmpty: false, isVisible: false, hasFullscreenWindows: false),
            WorkspaceViewModel(name: "setUpWorkspacesForTests", suffix: "", isFocused: false, isEffectivelyEmpty: true, isVisible: false, hasFullscreenWindows: false),
        ])
    }

    @Test
    func testUpdateTrayText_nonMainModeAndFullscreen() {
        world.activeMode = "service"
        defer { world.activeMode = mainModeId }
        setUpTree("h_tiles(2)", workspace: "b")
        setUpTree("h_tiles(*1)", workspace: "a")
        testWindow(1).isFullscreen = true
        testWindow(2).isFullscreen = true

        updateTrayText()

        let model = TrayMenuModel.shared
        #expect(model.trayText == "(S) [a]")
        #expect(model.trayItems == [
            TrayItem(type: .mode, name: "S", isActive: true, hasFullscreenWindows: false),
            TrayItem(type: .workspace, name: "a", isActive: true, hasFullscreenWindows: true),
        ])
        #expect(model.workspaces == [
            WorkspaceViewModel(name: "a", suffix: " - bobko.AeroSpace.test-app", isFocused: true, isEffectivelyEmpty: false, isVisible: true, hasFullscreenWindows: true),
            WorkspaceViewModel(name: "b", suffix: " - bobko.AeroSpace.test-app", isFocused: false, isEffectivelyEmpty: false, isVisible: false, hasFullscreenWindows: true),
            WorkspaceViewModel(name: "setUpWorkspacesForTests", suffix: "", isFocused: false, isEffectivelyEmpty: true, isVisible: false, hasFullscreenWindows: false),
        ])
    }

    @Test
    func testUpdateTrayText_emptyFocusedWorkspace() {
        updateTrayText()

        let model = TrayMenuModel.shared
        #expect(model.trayText == "setUpWorkspacesForTests")
        #expect(model.trayItems == [
            TrayItem(type: .workspace, name: "setUpWorkspacesForTests", isActive: true, hasFullscreenWindows: false),
        ])
        #expect(model.workspaces == [
            WorkspaceViewModel(name: "setUpWorkspacesForTests", suffix: " - Test Monitor", isFocused: true, isEffectivelyEmpty: true, isVisible: true, hasFullscreenWindows: false),
        ])
    }

    @Test
    func testUpdateTrayText_notifiesOnlyChangedValues() {
        updateTrayText()
        #expect(notifiedProperties { updateTrayText() } == [])

        setUpTree("h_tiles(*1)", workspace: "a")
        #expect(notifiedProperties { updateTrayText() } == ["trayText", "workspaces", "trayItems"])
    }

    @Test
    func testUpdateTrayText_notifiesAppearanceChange() {
        let app = NSApplication.shared
        let prevAppearance = app.appearance
        defer {
            app.appearance = prevAppearance
            updateTrayText()
        }
        app.appearance = NSAppearance(named: .aqua)
        updateTrayText()
        #expect(TrayMenuModel.shared.appearanceTheme == .light)

        // The tray text stays the same, but the menu must still be rebuilt with the new appearance
        let notified = notifiedProperties {
            app.appearance = NSAppearance(named: .darkAqua)
            updateTrayText()
        }
        #expect(TrayMenuModel.shared.appearanceTheme == .dark)
        #expect(notified == ["appearanceTheme"])
    }

    /// The views re-render only on the changes they observe
    @Test
    func testEveryDisplayedPropertyNotifies() {
        let model = TrayMenuModel.shared
        func expectNotifies<T>(_ keyPath: ReferenceWritableKeyPath<TrayMenuModel, T>, _ newValue: T, _ name: String) {
            let prev = model[keyPath: keyPath]
            defer { model[keyPath: keyPath] = prev }
            #expect(notifiedProperties { model[keyPath: keyPath] = newValue } == [name], "\(name)")
        }
        expectNotifies(\.trayText, "changed", "trayText")
        expectNotifies(\.trayItems, [TrayItem(type: .mode, name: "S", isActive: true, hasFullscreenWindows: false)], "trayItems")
        expectNotifies(\.isEnabled, !model.isEnabled, "isEnabled")
        expectNotifies(\.workspaces, [WorkspaceViewModel(name: "changed", suffix: "", isFocused: true, isEffectivelyEmpty: true, isVisible: true, hasFullscreenWindows: false)], "workspaces")
        expectNotifies(\.sponsorshipMessage, model.sponsorshipMessage + " changed", "sponsorshipMessage")
        expectNotifies(\.axPermissionStatus, model.axPermissionStatus == .granted ? .waiting : .granted, "axPermissionStatus")
        expectNotifies(\.appearanceTheme, model.appearanceTheme == .dark ? .light : .dark, "appearanceTheme")
        expectNotifies(\.textEditorToOpenConfig, URL(filePath: "/changed"), "textEditorToOpenConfig")
        withPreservedMenuBarStyle {
            expectNotifies(\.menuBarStyle, model.menuBarStyle == .squares ? .i3 : .squares, "menuBarStyle")
        }
    }

    /// The menu bar icon opens the config diagnostics window in its onChange(of: message).
    /// SwiftUI runs it only if the icon's body reads the message
    @Test
    func testMenuBarIconBodyObservesTheMessage() {
        let messageModel = MessageModel.shared
        let prevMessage = messageModel.message
        defer { messageModel.message = prevMessage }
        let notified = NotifiedProperties()
        withObservationTracking {
            _ = MenuBarIcon(viewModel: .shared, messageModel: messageModel).body
        } onChange: {
            notified.insert("body")
        }
        messageModel.message = Message(body: "changed")
        #expect(notified.names == ["body"])
    }

    /// The users' choice survives the update: the key is the same as before
    @Test
    func testMenuBarStyleIsStoredInUserDefaults() {
        withPreservedMenuBarStyle {
            let model = TrayMenuModel.shared
            model.menuBarStyle = .i3Ordered
            #expect(UserDefaults.standard.string(forKey: "displayStyle") == "i3Ordered")
            UserDefaults.standard.set("squares", forKey: "displayStyle")
            #expect(model.menuBarStyle == .squares)
            UserDefaults.standard.removeObject(forKey: "displayStyle")
            #expect(model.menuBarStyle == .monospacedText)
        }
    }

    @Test
    func testSystemImageName() {
        func imageName(_ name: String, _ type: TrayItemType = .workspace, isActive: Bool = false) -> String? {
            TrayItem(type: type, name: name, isActive: isActive, hasFullscreenWindows: false).systemImageName
        }
        #expect(imageName("0") == "0.square")
        #expect(imageName("50", isActive: true) == "50.square.fill")
        #expect(imageName("05") == "05.square")
        #expect(imageName("00", .mode) == "00.circle")
        #expect(imageName("51") == nil)
        #expect(imageName("-1") == nil)
        // Int() accepts these, but there are no such symbols
        #expect(imageName("+5") == nil)
        #expect(imageName("-0") == nil)
        #expect(imageName("005") == nil)
        #expect(imageName("050") == nil)
        #expect(imageName("A") == "a.square")
        #expect(imageName("Z", .mode) == "z.circle")
        #expect(imageName("a") == nil)
        #expect(imageName("AB") == nil)
        #expect(imageName("1A") == nil)
        #expect(imageName("é") == nil)
    }

    @Test
    func testSystemImageNameIsAnExistingSymbol() {
        let numbers = (0 ... 60).flatMap { [String($0), "0\($0)", "00\($0)", "+\($0)", "-\($0)"] }
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)
        for name in numbers + letters {
            for (type, isActive) in [(TrayItemType.mode, true), (.workspace, true), (.workspace, false)] {
                let item = TrayItem(type: type, name: name, isActive: isActive, hasFullscreenWindows: false)
                if let imageName = item.systemImageName, NSImage(systemSymbolName: imageName, accessibilityDescription: nil) == nil {
                    Issue.record("Workspace '\(name)' maps to '\(imageName)', which isn't an SF Symbol")
                }
            }
        }
    }
}

/// The names of the displayed TrayMenuModel properties whose observers `change` notifies
private func notifiedProperties(_ change: () -> Void) -> Set<String> {
    let model = TrayMenuModel.shared
    let reads: [String: () -> Void] = [
        "trayText": { _ = model.trayText },
        "trayItems": { _ = model.trayItems },
        "isEnabled": { _ = model.isEnabled },
        "workspaces": { _ = model.workspaces },
        "sponsorshipMessage": { _ = model.sponsorshipMessage },
        "axPermissionStatus": { _ = model.axPermissionStatus },
        "appearanceTheme": { _ = model.appearanceTheme },
        "textEditorToOpenConfig": { _ = model.textEditorToOpenConfig },
        "menuBarStyle": { _ = model.menuBarStyle },
    ]
    let notified = NotifiedProperties()
    for (name, read) in reads {
        withObservationTracking(read) { notified.insert(name) }
    }
    change()
    return notified.names
}

nonisolated private final class NotifiedProperties: Sendable {
    private let state = Mutex(Set<String>())
    var names: Set<String> { state.withLock { $0 } }
    func insert(_ name: String) { _ = state.withLock { $0.insert(name) } }
}

/// The tests write the menu bar style to the UserDefaults of the test process. Restore it
private func withPreservedMenuBarStyle(_ body: () -> Void) {
    let prev = UserDefaults.standard.object(forKey: "displayStyle")
    defer { UserDefaults.standard.set(prev, forKey: "displayStyle") }
    body()
}
