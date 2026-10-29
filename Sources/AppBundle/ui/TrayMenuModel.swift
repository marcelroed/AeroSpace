import AppKit
import Common
import Observation

/// The views re-render when a property that their body reads changes.
/// Assigning an equal value doesn't notify them
@Observable
final class TrayMenuModel {
    var trayText: String = ""
    var trayItems: [TrayItem] = []
    var workspaces: [WorkspaceViewModel] = []
    /// A copy of `world.isEnabled`, which the views can observe
    var isEnabled: Bool = true
    var sponsorshipMessage: String = sponsorshipPrompts.randomElement().orDie()
    var axPermissionStatus: AxPermissionStatus = .waitingWithPrompt
    // Only the menu shows these, and nothing notifies us when they change. They are polled when a menu opens, not on
    // every refresh: the editor lookup asks LaunchServices (about 100 µs)
    var appearanceTheme: AppearanceTheme = .current
    var textEditorToOpenConfig: URL = getTextEditorToOpenConfig()

    // periphery:ignore - assign-only: dropping the token removes the observation
    @ObservationIgnored private var menuOpenObservation: NotificationCenter.ObservationToken? = nil

    init() {
        menuOpenObservation = NotificationCenter.default.addObserver(of: NSMenu.self, for: .didBeginTracking) { [weak self] _ in
            self?.appearanceTheme = .current
            self?.textEditorToOpenConfig = getTextEditorToOpenConfig()
        }
    }

    /// Stored in UserDefaults
    var menuBarStyle: MenuBarStyle {
        get {
            access(keyPath: \.menuBarStyle)
            return UserDefaults.standard.string(forKey: menuBarStyleKey).flatMap(MenuBarStyle.init(rawValue:)) ?? .monospacedText
        }
        set {
            withMutation(keyPath: \.menuBarStyle) {
                UserDefaults.standard.set(newValue.rawValue, forKey: menuBarStyleKey)
                UserDefaults.standard.synchronize()
            }
        }
    }
}

private let menuBarStyleKey = "displayStyle"

enum AxPermissionStatus: Equatable {
    case granted
    case waiting
    case waitingWithPrompt
}

/// Runs on every refresh: the menu bar icon, and the menu's list of workspaces
func updateTrayText() {
    let monitors = world.monitors.all
    let focusedWorkspace = focus.workspace
    let modeLetter: String? = world.activeMode == mainModeId ? nil : world.activeMode?.first?.uppercased()
    let visibleWorkspaces = monitors.map { monitor in
        let workspace = monitor.activeWorkspace
        return TrayItem(
            type: .workspace,
            name: workspace.name,
            isActive: workspace == focusedWorkspace,
            hasFullscreenWindows: workspace.allLeafWindowsRecursive.hasFullscreenWindows,
        )
    }
    let workspaceTexts = visibleWorkspaces.map { item in
        let name = item.hasFullscreenWindows ? "[\(item.name)]" : item.name
        return (item.isActive && monitors.count > 1 ? "*" : "") + name
    }
    let modeItems = modeLetter.map { [TrayItem(type: .mode, name: $0, isActive: true, hasFullscreenWindows: false)] } ?? []

    let model = world.ui.trayMenuModel
    model.trayText = (modeLetter.map { "(\($0)) " } ?? "") + workspaceTexts.joined(separator: " │ ")
    model.trayItems = modeItems + visibleWorkspaces
    model.workspaces = Workspace.all.map { WorkspaceViewModel($0, isFocused: $0 == focusedWorkspace) }
}

extension [Window] {
    fileprivate var hasFullscreenWindows: Bool { contains { $0.isFullscreen } }
}

struct WorkspaceViewModel: Hashable {
    let name: String
    let appsOrMonitor: String
    let isFocused: Bool
    let isEffectivelyEmpty: Bool
    let isVisible: Bool
    let hasFullscreenWindows: Bool
}

extension WorkspaceViewModel {
    init(_ workspace: Workspace, isFocused: Bool) {
        let windows = workspace.allLeafWindowsRecursive
        let apps = windows.compactMap(\.app.name).filter { !$0.isEmpty }.toSet()
        let dash = " - "
        let appsOrMonitor = switch true {
            case !apps.isEmpty: dash + apps.sorted().joinTruncating(separator: ", ", length: 25)
            case workspace.isVisible: dash + workspace.workspaceMonitor.name
            default: ""
        }
        self.init(
            name: workspace.name,
            appsOrMonitor: appsOrMonitor,
            isFocused: isFocused,
            isEffectivelyEmpty: workspace.isEffectivelyEmpty,
            isVisible: workspace.isVisible,
            hasFullscreenWindows: windows.hasFullscreenWindows,
        )
    }
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
