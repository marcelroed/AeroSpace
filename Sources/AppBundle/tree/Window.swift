import AppKit
import Common

open class Window: TreeNode, Hashable {
    nonisolated let windowId: WindowId
    let app: any AbstractApp
    var lastFloatingSize: CGSize?
    var isFullscreen: Bool = false
    var noOuterGapsInFullscreen: Bool = false
    var layoutReason: LayoutReason = .standard

    /// Registers the window in ``World/windows``
    init(id: WindowId, _ app: any AbstractApp, lastFloatingSize: CGSize?, parent: Container, weight: CGFloat?, index: Int?) {
        self.windowId = id
        self.app = app
        self.lastFloatingSize = lastFloatingSize
        super.init(parent: parent, weight: weight, index: index)
        check(world.windows.updateValue(self, forKey: id) == nil, "Window \(id) is already registered")
    }

    static func get(byId windowId: WindowId) -> Window? { world.windows[windowId] } // todo make non optional

    func closeAxWindow() { die("Not implemented") }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(windowId)
    }

    func getAxSize(_ cm: CancellationMode) async throws -> CGSize? { die("Not implemented") }
    func getTitle(_ cm: CancellationMode) async throws -> String { die("Not implemented") }
    func isMacosFullscreen(_ cm: CancellationMode) async throws -> Bool { false }
    func isMacosMinimized(_ cm: CancellationMode) async throws -> Bool { false } // todo replace with enum MacOsWindowNativeState { normal, fullscreen, invisible }
    /// isMinimized is false if isFullscreen
    func getMacosFullscreenAndMinimized(_ cm: CancellationMode) async throws -> (isFullscreen: Bool, isMinimized: Bool) {
        if try await isMacosFullscreen(cm) { return (true, false) }
        return (false, try await isMacosMinimized(cm))
    }
    var isHiddenInCorner: Bool { die("Not implemented") }
    func nativeFocus() { die("Not implemented") }
    func getAxRect(_ cm: CancellationMode) async throws -> Rect? { die("Not implemented") }
    func getCenter(_ cm: CancellationMode) async throws -> CGPoint? { try await getAxRect(cm)?.center }

    func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) { die("Not implemented") }
}

enum LayoutReason: Equatable {
    case standard
    /// Reason for the cur temp layout is macOS native fullscreen, minimize, or hide
    case macos(prevParentKind: ContainerKind)
}

/// A window's parent, typed. The parent of a window is always a container. The containers of a workspace carry it
enum WindowPlacement: Equatable {
    case tiling(TilingContainer)
    case floating(Workspace)
    case macosFullscreen(Workspace)
    case macosHiddenApp(Workspace)
    case macosMinimized
    case macosPopup
}

/// Where a window is on its workspace: the placement of a focused window, see ``LiveFocus``. Minimized, popup and unbound
/// windows have none
enum WorkspacePlacement {
    case tiling(TilingContainer)
    case floating, macosFullscreen, macosHiddenApp
}

extension Window {
    /// nil while the window is unbound
    var placement: WindowPlacement? {
        guard let parent = parent as? Container else { return nil }
        let workspace = parent.parent as? Workspace // The parent of a floating, fullscreen or hidden-app container
        return switch parent.kind {
            case .tiling: .tiling(parent as? TilingContainer ?? dieT("A tiling container must be a TilingContainer"))
            case .floating: workspace.map { .floating($0) }
            case .macosFullscreen: workspace.map { .macosFullscreen($0) }
            case .macosHiddenApp: workspace.map { .macosHiddenApp($0) }
            case .macosMinimized: .macosMinimized
            case .macosPopup: .macosPopup
        }
    }

    /// The window's workspace and where the window is there. nil for the minimized, popup and unbound windows
    var workspacePlacement: (workspace: Workspace, placement: WorkspacePlacement)? {
        switch placement {
            case .tiling(let parent): parent.nodeWorkspace.map { ($0, .tiling(parent)) }
            case .floating(let workspace): (workspace, .floating)
            case .macosFullscreen(let workspace): (workspace, .macosFullscreen)
            case .macosHiddenApp(let workspace): (workspace, .macosHiddenApp)
            case .macosMinimized, .macosPopup, nil: nil
        }
    }

    var isFloating: Bool { (parent as? Container)?.kind == .floating } // todo drop. It will be a source of bugs when sticky is introduced

    func asMacWindow() -> MacWindow { self as! MacWindow }
}
