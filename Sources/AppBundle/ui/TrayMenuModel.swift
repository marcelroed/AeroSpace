import AppKit
import Common

@MainActor
public final class TrayMenuModel: ObservableObject {
    public static let shared = TrayMenuModel()

    private init() {}

    @Published var trayText: String = ""
    @Published var trayItems: [TrayItem] = []
    /// Is "layouting" enabled
    @Published var isEnabled: Bool = true
    @Published var workspaces: [WorkspaceViewModel] = []
    @Published var experimentalUISettings: ExperimentalUISettings = ExperimentalUISettings()
    @Published var sponsorshipMessage: String = sponsorshipPrompts.randomElement().orDie()
    @Published var lastReloadConfigContainedWarnings: Bool = false
    @Published var axPermissionStatus: AxPermissionStatus = .waitingWithPrompt
    // Polled by updateTrayText, since nothing notifies us when these change
    @Published var appearanceTheme: AppearanceTheme = .current
    @Published var textEditorToOpenConfig: URL = getTextEditorToOpenConfig()
}

enum AxPermissionStatus: Equatable {
    case granted
    case waiting
    case waitingWithPrompt
}

@MainActor func updateTrayText() {
    let sortedMonitors = sortedMonitorInfos
    let focusedWorkspace = focus.workspace
    // activeWorkspace may rearrange workspaces on monitors. Evaluate it once per monitor, before Workspace.all
    let activeWorkspaces = sortedMonitors.map { monitor in
        let workspace = monitor.activeWorkspace
        return (workspace: workspace, hasFullscreenWindows: workspace.allLeafWindowsRecursive.hasFullscreenWindows)
    }
    let modeLetter: String? = activeMode?.takeIf { $0 != mainModeId }?.first.map { $0.uppercased() }

    let trayText = (modeLetter.map { "(\($0)) " } ?? "") +
        activeWorkspaces
        .map { workspace, hasFullscreenWindows in
            let name = hasFullscreenWindows ? "[\(workspace.name)]" : workspace.name
            return (workspace == focusedWorkspace && sortedMonitors.count > 1 ? "*" : "") + name
        }
        .joined(separator: " │ ")
    let workspaces = Workspace.all.map { workspace in
        let windows = workspace.allLeafWindowsRecursive
        let apps = windows.compactMap { $0.app.name?.takeIf { !$0.isEmpty } }.toSet()
        let dash = " - "
        let suffix = switch true {
            case !apps.isEmpty: dash + apps.sorted().joinTruncating(separator: ", ", length: 25)
            case workspace.isVisible: dash + workspace.workspaceMonitor.name
            default: ""
        }
        return WorkspaceViewModel(
            name: workspace.name,
            suffix: suffix,
            isFocused: focusedWorkspace == workspace,
            isEffectivelyEmpty: workspace.isEffectivelyEmpty,
            isVisible: workspace.isVisible,
            hasFullscreenWindows: windows.hasFullscreenWindows,
        )
    }
    var trayItems = activeWorkspaces.map { workspace, hasFullscreenWindows in
        TrayItem(type: .workspace, name: workspace.name, isActive: workspace == focusedWorkspace, hasFullscreenWindows: hasFullscreenWindows)
    }
    if let modeLetter {
        trayItems.insert(TrayItem(type: .mode, name: modeLetter, isActive: true, hasFullscreenWindows: false), at: 0)
    }

    // Every @Published assignment invalidates SwiftUI views (and re-renders the menu bar image) even if the value
    // didn't change. updateTrayText runs on every refresh session, so only assign the values that changed
    let model = TrayMenuModel.shared
    if model.trayText != trayText { model.trayText = trayText }
    if model.workspaces != workspaces { model.workspaces = workspaces }
    if model.trayItems != trayItems { model.trayItems = trayItems }
    // The menu also shows values that nothing notifies us about. Poll them here, so that the first refresh after they
    // change still rebuilds the menu
    let appearanceTheme = AppearanceTheme.current
    if model.appearanceTheme != appearanceTheme { model.appearanceTheme = appearanceTheme }
    let textEditorToOpenConfig = getTextEditorToOpenConfig()
    if model.textEditorToOpenConfig != textEditorToOpenConfig { model.textEditorToOpenConfig = textEditorToOpenConfig }
}

extension [Window] {
    @MainActor fileprivate var hasFullscreenWindows: Bool { contains { $0.isFullscreen } }
}

struct WorkspaceViewModel: Hashable {
    let name: String
    let suffix: String
    let isFocused: Bool
    let isEffectivelyEmpty: Bool
    let isVisible: Bool
    let hasFullscreenWindows: Bool
}

enum TrayItemType: String {
    case mode
    case workspace
}

private let validLetters = "A" ... "Z"

struct TrayItem: Hashable, Identifiable {
    let type: TrayItemType
    let name: String
    let isActive: Bool
    let hasFullscreenWindows: Bool
    var systemImageName: String? {
        // System image type is only valid for numbers 0 to 50 (also 00 to 09) and single capital char workspace name.
        // Int(name) also accepts names such as "+5", "-0" and "005", which have no system image
        let isSupported = if let number = Int(name) {
            (0 ... 50).contains(number) && name.count <= 2 && name.allSatisfy(\.isWholeNumber)
        } else {
            name.count == 1 && validLetters.contains(name)
        }
        guard isSupported else { return nil }
        let lowercasedName = name.lowercased()
        return switch type {
            case .mode: "\(lowercasedName).circle"
            case .workspace where isActive: "\(lowercasedName).square.fill"
            case .workspace: "\(lowercasedName).square"
        }
    }
    var id: String {
        return type.rawValue + name
    }
}
