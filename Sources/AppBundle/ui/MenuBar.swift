import Common
import Foundation
import SwiftUI

@MainActor
public func menuBar(viewModel: TrayMenuModel) -> some Scene { // todo should it be converted to "SwiftUI struct"?
    MenuBarExtra {
        let shortIdentification = "\(aeroSpaceAppName) v\(aeroSpaceAppVersion) \(gitShortHash)"
        let identification      = "\(aeroSpaceAppName) v\(aeroSpaceAppVersion) \(gitHash)"
        Text(shortIdentification)
        Button("Copy to clipboard") { identification.copyToClipboard() }
            .keyboardShortcut("C", modifiers: .command)
        Divider()

        if viewModel.axPermissionStatus == .granted {
            if let token: RunSessionGuard = .isServerEnabled, viewModel.lastReloadConfigContainedWarnings {
                configWarningsButton(token)
                Divider()
            }
            if let token: RunSessionGuard = .isServerEnabled {
                workspacesSection(viewModel, token)
                Divider()
            }
            sponsorButton(viewModel)
            Divider()
            enableToggleButton(viewModel)
            getExperimentalUISettingsMenu(viewModel: viewModel)
            openConfigButton(editor: viewModel.textEditorToOpenConfig)
            reloadConfigButton(warningsAsErrors: false)
        } else {
            Button("AeroSpace requires accessibility permission to move windows") {
                viewModel.axPermissionStatus = .waitingWithPrompt
            }
        }
        quitButton()
    } label: {
        menuBarIcon(viewModel)
    }
}

@MainActor
private func configWarningsButton(_ token: RunSessionGuard) -> some View {
    Button {
        reloadConfigFromMenu(token, warningsAsErrors: true)
    } label: {
        Label("Config contains warnings...", systemImage: "exclamationmark.triangle.fill")
    }
}

@MainActor @ViewBuilder
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

@MainActor
private func sponsorButton(_ viewModel: TrayMenuModel) -> some View {
    Button {
        NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/nikitabobko").orDie())
        viewModel.sponsorshipMessage = sponsorshipPrompts.randomElement().orDie()
    } label: {
        Text("Sponsor AeroSpace on GitHub")
        Text(viewModel.sponsorshipMessage)
    }
}

@MainActor
private func enableToggleButton(_ viewModel: TrayMenuModel) -> some View {
    Button(viewModel.isEnabled ? "Disable" : "Enable") {
        Task.startUnstructured {
            try await runLightSession(.menuBarButton, .forceRun) {
                _ = await EnableCommand(args: EnableCmdArgs(rawArgs: [], targetState: .toggle))
                    .run(.defaultEnv, .emptyStdin)
            }
        }
    }.keyboardShortcut("E", modifiers: .command)
}

@MainActor
private func quitButton() -> some View {
    Button("Quit \(aeroSpaceAppName)") {
        Task.startUnstructured {
            terminationHandler?.beforeTermination()
            terminateApp()
        }
    }.keyboardShortcut("Q", modifiers: .command)
}

@MainActor @ViewBuilder
private func menuBarIcon(_ viewModel: TrayMenuModel) -> some View {
    switch (viewModel.axPermissionStatus, viewModel.isEnabled) {
        case (.granted, true):
            MenuBarLabel().environmentObject(viewModel)
        case (.granted, false):
            Image(systemName: "pause.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
        default:
            Image(systemName: "exclamationmark.triangle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
    }
}

@MainActor @ViewBuilder
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

@MainActor @ViewBuilder
func reloadConfigButton(showShortcutGroup: Bool = false, warningsAsErrors: Bool) -> some View {
    if let token: RunSessionGuard = .isServerEnabled {
        let button = Button("Reload config") {
            reloadConfigFromMenu(token, warningsAsErrors: warningsAsErrors)
        }.keyboardShortcut("R", modifiers: .command)
        switch showShortcutGroup {
            case true: shortcutGroup(label: Text("⌘ R"), content: button)
            case false: button
        }
    }
}

@MainActor
private func reloadConfigFromMenu(_ token: RunSessionGuard, warningsAsErrors: Bool) {
    Task.startUnstructured {
        try await runLightSession(.menuBarButton, token) {
            let args: ReloadConfigCmdArgs = ReloadConfigCmdArgs(rawArgs: []).copy(\.warningsAsErrors, warningsAsErrors)
            _ = await reloadConfig_nonCancellable(args: args)
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
    NSWorkspace.shared.urlForApplication(toOpen: findCustomConfigUrl().urlOrNil ?? defaultConfigUrl)?
        .takeIf { $0.lastPathComponent != "Xcode.app" } // Blacklist Xcode. It is too heavy to open plain text files
        ?? URL(filePath: "/System/Applications/TextEdit.app")
}
