import Common
import Foundation
import SwiftUI

public func menuBar(viewModel: TrayMenuModel, messageModel: MessageModel) -> some Scene {
    MenuBarExtra {
        MenuBarMenu(viewModel: viewModel)
    } label: {
        MenuBarIcon(viewModel: viewModel, messageModel: messageModel)
    }
}

// The views that show the model's state are View structs whose body reads it. Then a change re-renders them.
// Re-evaluating the scene doesn't update the menu (see MenuBarStyleButton)
private struct MenuBarMenu: View {
    let viewModel: TrayMenuModel

    var body: some View {
        let shortIdentification = "\(aeroSpaceAppName) v\(aeroSpaceAppVersion) \(gitShortHash)"
        let identification      = "\(aeroSpaceAppName) v\(aeroSpaceAppVersion) \(gitHash)"
        Text(shortIdentification)
        Button("Copy to clipboard") {
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([.string], owner: nil)
            pasteboard.setString(identification, forType: .string)
        }.keyboardShortcut("C", modifiers: .command)
        Divider()

        if viewModel.axPermissionStatus == .granted {
            if let token: RunSessionGuard = .isServerEnabled {
                workspacesSection(viewModel, token)
                Divider()
            }
            sponsorButton(viewModel)
            Divider()
            enableToggleButton(viewModel)
            getExperimentalUISettingsMenu(viewModel: viewModel)
            openConfigButton(editor: viewModel.textEditorToOpenConfig)
            reloadConfigButton()
        } else {
            Button("AeroSpace requires accessibility permission to move windows") {
                viewModel.axPermissionStatus = .waitingWithPrompt
            }
        }
        quitButton()
    }
}

@ViewBuilder
private func workspacesSection(_ viewModel: TrayMenuModel, _ token: RunSessionGuard) -> some View {
    Text("Workspaces:")
    ForEach(viewModel.workspaces, id: \.name) { workspace in
        Button {
            Task.startUnstructured {
                try await runLightSession(.menuBarButton, token) { _ = Workspace.get(byName: workspace.name).focusWorkspace() }
            }
        } label: {
            Toggle(isOn: .constant(workspace.isFocused)) {
                Text(workspace.name + workspace.suffix).font(.system(.body, design: .monospaced))
            }
        }
    }
}

private func sponsorButton(_ viewModel: TrayMenuModel) -> some View {
    Button {
        NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/nikitabobko").orDie())
        viewModel.sponsorshipMessage = sponsorshipPrompts.randomElement().orDie()
    } label: {
        Text("Sponsor AeroSpace on GitHub")
        Text(viewModel.sponsorshipMessage)
    }
}

private func enableToggleButton(_ viewModel: TrayMenuModel) -> some View {
    Button(viewModel.isEnabled ? "Disable" : "Enable") {
        Task.startUnstructured {
            try await runLightSession(.menuBarButton, .forceRun) {
                _ = await EnableCommand(targetState: .toggle)
                    .run(.defaultEnv, .emptyStdin)
            }
        }
    }.keyboardShortcut("E", modifiers: .command)
}

private func quitButton() -> some View {
    Button("Quit \(aeroSpaceAppName)") {
        Task.startUnstructured {
            terminationHandler?.beforeTermination()
            terminateApp()
        }
    }.keyboardShortcut("Q", modifiers: .command)
}

/// The menu bar extra's label. The extra has no isInserted binding, so the label lives as long as the app. That makes
/// it the view that opens the config diagnostics window: SwiftUI documents Observation tracking for a View's body,
/// not for the App's or a Scene's body
struct MenuBarIcon: View {
    let viewModel: TrayMenuModel
    let messageModel: MessageModel
    @Environment(\.openWindow) private var openWindow: OpenWindowAction

    var body: some View {
        // initial: the message may be set before the label first appears (a config error at startup)
        icon.onChange(of: messageModel.message, initial: true) { _, message in
            if message != nil {
                openWindow(id: messageWindowId)
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        let granted = viewModel.axPermissionStatus == .granted
        if granted && viewModel.isEnabled {
            MenuBarLabel(viewModel: viewModel)
        } else {
            Image(systemName: granted ? "pause.circle.fill" : "exclamationmark.triangle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

@ViewBuilder
func openConfigButton(editor: URL = getTextEditorToOpenConfig(), showShortcutGroup: Bool = false) -> some View {
    let button = Button("Open config in '\(editor.lastPathComponent)'") {
        let fallbackConfig: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: configDotfileName)
        switch findCustomConfigUrl() {
            case .file(let url):
                if !FileManager.default.fileExists(atPath: url.path) { // The --config-path file was deleted after the startup
                    _ = try? FileManager.default.copyItem(atPath: defaultConfigUrl.path, toPath: url.path)
                }
                url.open(with: editor)
            case .noCustomConfigExists:
                _ = try? FileManager.default.copyItem(atPath: defaultConfigUrl.path, toPath: fallbackConfig.path)
                fallbackConfig.open(with: editor)
            case .ambiguousConfigError:
                fallbackConfig.open(with: editor)
        }
    }.keyboardShortcut(",", modifiers: .command)
    switch showShortcutGroup {
        case true: shortcutGroup(label: Text("⌘ ,"), content: button)
        case false: button
    }
}

@ViewBuilder
func reloadConfigButton(showShortcutGroup: Bool = false) -> some View {
    if let token: RunSessionGuard = .isServerEnabled {
        let button = Button("Reload config") {
            reloadConfigFromMenu(token)
        }.keyboardShortcut("R", modifiers: .command)
        switch showShortcutGroup {
            case true: shortcutGroup(label: Text("⌘ R"), content: button)
            case false: button
        }
    }
}

private func reloadConfigFromMenu(_ token: RunSessionGuard) {
    Task.startUnstructured {
        try await runLightSession(.menuBarButton, token) {
            _ = await reloadConfig_nonCancellable()
        }
    }
}

func shortcutGroup(label: some View, content: some View) -> some View {
    GroupBox {
        VStack(alignment: .trailing, spacing: 6) {
            label
                .foregroundStyle(Color.secondary)
            content
        }
    }
}

func getTextEditorToOpenConfig() -> URL {
    // urlForApplication(toOpen:) returns nil for a missing file, e.g. a deleted --config-path file.
    // "Open config" recreates such a file from the default config
    let config = findCustomConfigUrl().urlOrNil?.takeIf { FileManager.default.fileExists(atPath: $0.path) } ?? defaultConfigUrl
    return NSWorkspace.shared.urlForApplication(toOpen: config)?
        .takeIf { $0.lastPathComponent != "Xcode.app" } // Blacklist Xcode. It is too heavy to open plain text files
        ?? URL(filePath: "/System/Applications/TextEdit.app")
}
