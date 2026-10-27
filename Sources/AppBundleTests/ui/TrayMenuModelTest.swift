@testable import AppBundle
import AppKit
import Common
import Observation
import Synchronization
import Testing

@Suite(.aeroSpaceGlobalState)
struct TrayMenuModelTest {
    nonisolated enum TrayTree: Sendable {
        /// Only the empty focused workspace
        case empty
        /// Window 1 focused on workspace a, window 2 on workspace b
        case twoWorkspaces(fullscreen: Bool)
    }

    struct TrayCase: Sendable, CustomTestStringConvertible {
        let tree: TrayTree
        let mode: String
        let text: String
        let items: [TrayItem]
        let workspaces: [WorkspaceViewModel]
        var testDescription: String { "\(tree) in mode \(mode)" }
    }

    @Test(arguments: [
        TrayCase(tree: .empty, mode: mainModeId, text: "setUpWorkspacesForTests", items: [
            TrayItem(type: .workspace, name: "setUpWorkspacesForTests", isActive: true, hasFullscreenWindows: false),
        ], workspaces: [
            WorkspaceViewModel(name: "setUpWorkspacesForTests", appsOrMonitor: " - Test Monitor", isFocused: true, isEffectivelyEmpty: true, isVisible: true, hasFullscreenWindows: false),
        ]),
        TrayCase(tree: .twoWorkspaces(fullscreen: false), mode: mainModeId, text: "a", items: [
            TrayItem(type: .workspace, name: "a", isActive: true, hasFullscreenWindows: false),
        ], workspaces: [
            WorkspaceViewModel(name: "a", appsOrMonitor: " - bobko.AeroSpace.test-app", isFocused: true, isEffectivelyEmpty: false, isVisible: true, hasFullscreenWindows: false),
            WorkspaceViewModel(name: "b", appsOrMonitor: " - bobko.AeroSpace.test-app", isFocused: false, isEffectivelyEmpty: false, isVisible: false, hasFullscreenWindows: false),
            WorkspaceViewModel(name: "setUpWorkspacesForTests", appsOrMonitor: "", isFocused: false, isEffectivelyEmpty: true, isVisible: false, hasFullscreenWindows: false),
        ]),
        TrayCase(tree: .twoWorkspaces(fullscreen: true), mode: "service", text: "(S) [a]", items: [
            TrayItem(type: .mode, name: "S", isActive: true, hasFullscreenWindows: false),
            TrayItem(type: .workspace, name: "a", isActive: true, hasFullscreenWindows: true),
        ], workspaces: [
            WorkspaceViewModel(name: "a", appsOrMonitor: " - bobko.AeroSpace.test-app", isFocused: true, isEffectivelyEmpty: false, isVisible: true, hasFullscreenWindows: true),
            WorkspaceViewModel(name: "b", appsOrMonitor: " - bobko.AeroSpace.test-app", isFocused: false, isEffectivelyEmpty: false, isVisible: false, hasFullscreenWindows: true),
            WorkspaceViewModel(name: "setUpWorkspacesForTests", appsOrMonitor: "", isFocused: false, isEffectivelyEmpty: true, isVisible: false, hasFullscreenWindows: false),
        ]),
    ] as [TrayCase])
    func trayShowsTheVisibleWorkspaces(_ row: TrayCase) {
        world.activeMode = row.mode
        defer { world.activeMode = mainModeId }
        if case .twoWorkspaces(let fullscreen) = row.tree {
            setUpTree("h_tiles(2)", workspace: "b")
            setUpTree("h_tiles(*1)", workspace: "a")
            testWindow(1).isFullscreen = fullscreen
            testWindow(2).isFullscreen = fullscreen
        }

        updateTrayText()

        let model = world.ui.trayMenuModel
        expectEqual(model.trayText, row.text)
        expectEqual(model.trayItems, row.items)
        expectEqual(model.workspaces, row.workspaces)
    }

    @Test
    func updateTrayTextNotifiesOnlyChangedValues() {
        updateTrayText()
        expectEqual(notifiedProperties { updateTrayText() }, [])

        setUpTree("h_tiles(*1)", workspace: "a")
        expectEqual(notifiedProperties { updateTrayText() }, ["trayText", "workspaces", "trayItems"])
    }

    /// Nothing notifies us when the appearance or the editor of .toml files changes. Opening a menu polls them, so the
    /// menu shows the new values; a refresh doesn't
    @Test
    func openingAMenuPollsTheAppearanceAndTheEditor() {
        let app = NSApplication.shared
        let prevAppearance = app.appearance
        defer { app.appearance = prevAppearance }
        let model = world.ui.trayMenuModel
        func openMenu() { NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu()) }
        app.appearance = NSAppearance(named: .aqua)
        openMenu()
        expectEqual(model.appearanceTheme, .light)

        updateTrayText()
        app.appearance = NSAppearance(named: .darkAqua)
        expectEqual(notifiedProperties { updateTrayText() }, [])
        expectEqual(model.appearanceTheme, .light)
        expectEqual(notifiedProperties { openMenu() }, ["appearanceTheme"])
        expectEqual(model.appearanceTheme, .dark)

        let staleEditor = URL(filePath: "/stale-editor.app")
        model.textEditorToOpenConfig = staleEditor
        openMenu()
        expectEqual(model.textEditorToOpenConfig, getTextEditorToOpenConfig())
    }

    /// The views re-render only on the changes they observe
    @Test
    func testEveryDisplayedPropertyNotifies() {
        let model = world.ui.trayMenuModel
        func expectNotifies<T>(_ keyPath: ReferenceWritableKeyPath<TrayMenuModel, T>, _ newValue: T, _ name: String) {
            let prev = model[keyPath: keyPath]
            defer { model[keyPath: keyPath] = prev }
            expectEqual(notifiedProperties { model[keyPath: keyPath] = newValue }, [name], "\(name)")
        }
        expectNotifies(\.trayText, "changed", "trayText")
        expectNotifies(\.trayItems, [TrayItem(type: .mode, name: "S", isActive: true, hasFullscreenWindows: false)], "trayItems")
        expectNotifies(\.isEnabled, !model.isEnabled, "isEnabled")
        expectNotifies(\.workspaces, [WorkspaceViewModel(name: "changed", appsOrMonitor: "", isFocused: true, isEffectivelyEmpty: true, isVisible: true, hasFullscreenWindows: false)], "workspaces")
        expectNotifies(\.sponsorshipMessage, model.sponsorshipMessage + " changed", "sponsorshipMessage")
        expectNotifies(\.axPermissionStatus, model.axPermissionStatus == .granted ? .waiting : .granted, "axPermissionStatus")
        expectNotifies(\.appearanceTheme, model.appearanceTheme == .dark ? .light : .dark, "appearanceTheme")
        expectNotifies(\.textEditorToOpenConfig, URL(filePath: "/changed"), "textEditorToOpenConfig")
        withPreservedMenuBarStyle {
            expectNotifies(\.menuBarStyle, model.menuBarStyle == .squares ? .i3 : .squares, "menuBarStyle")
        }
    }

    /// The menu bar icon re-renders on the message and on isEnabled:
    /// - It opens the config diagnostics window in its onChange(of: message). SwiftUI runs that only if the icon's
    ///   body reads the message.
    /// - World isn't observable: the menu bar shows `world.isEnabled` through the model's copy
    @Test
    func menuBarIconRerendersOnTheMessageAndOnIsEnabled() {
        let model = world.ui.trayMenuModel
        let messageModel = world.ui.messageModel
        let prevStatus = model.axPermissionStatus
        let prevMessage = messageModel.message
        defer {
            model.axPermissionStatus = prevStatus
            messageModel.message = prevMessage
            world.isEnabled = true
        }
        func isRerendered(by change: () -> Void) -> Bool {
            let notified = NotifiedProperties()
            withObservationTracking {
                _ = MenuBarIcon(viewModel: model, messageModel: messageModel).body
            } onChange: {
                notified.insert("body")
            }
            change()
            return notified.names == ["body"]
        }
        model.axPermissionStatus = .waitingWithPrompt // A config error at startup shows before the permission too
        #expect(isRerendered { messageModel.message = Message(body: "changed") }, "message")
        model.axPermissionStatus = .granted // Otherwise the icon doesn't read isEnabled
        #expect(isRerendered { world.isEnabled = false }, "isEnabled")
        #expect(!model.isEnabled)
        world.isEnabled = true
        #expect(model.isEnabled)
    }

    /// The users' choice survives the update: the key is the same as before
    @Test
    func testMenuBarStyleIsStoredInUserDefaults() {
        withPreservedMenuBarStyle {
            let model = world.ui.trayMenuModel
            model.menuBarStyle = .i3Ordered
            expectEqual(UserDefaults.standard.string(forKey: "displayStyle"), "i3Ordered")
            UserDefaults.standard.set("squares", forKey: "displayStyle")
            expectEqual(model.menuBarStyle, .squares)
            UserDefaults.standard.removeObject(forKey: "displayStyle")
            expectEqual(model.menuBarStyle, .monospacedText)
        }
    }

    @Test
    func testSystemImageName() {
        func imageName(_ name: String, _ type: TrayItemType = .workspace, isActive: Bool = false) -> String? {
            TrayItem(type: type, name: name, isActive: isActive, hasFullscreenWindows: false).systemImageName
        }
        expectEqual(imageName("0"), "0.square")
        expectEqual(imageName("50", isActive: true), "50.square.fill")
        expectEqual(imageName("05"), "05.square")
        expectEqual(imageName("00", .mode), "00.circle")
        expectEqual(imageName("51"), nil)
        expectEqual(imageName("-1"), nil)
        expectEqual(imageName("A"), "a.square")
        expectEqual(imageName("Z", .mode), "z.circle")
        expectEqual(imageName("a"), nil)
        expectEqual(imageName("AB"), nil)
        expectEqual(imageName("1A"), nil)
        expectEqual(imageName("é"), nil)
    }

    @Test
    func testSystemImageNameIsAnExistingSymbol() {
        let numbers = (0 ... 60).flatMap { (n: Int) -> [String] in ["\(n)", "0\(n)", "00\(n)", "+\(n)", "-\(n)"] }
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { String($0) }
        for name in numbers + letters {
            for (type, isActive) in [(.mode, true), (.workspace, true), (.workspace, false)] as [(TrayItemType, Bool)] {
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
    let model = world.ui.trayMenuModel
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
