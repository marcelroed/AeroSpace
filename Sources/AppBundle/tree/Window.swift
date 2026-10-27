import AppKit
import Common

final class Window: TreeNode, Hashable {
    nonisolated let windowId: WindowId
    let app: AppInfo
    var isFullscreen: Bool = false
    var noOuterGapsInFullscreen: Bool = false
    var layoutReason: LayoutReason = .standard

    /// Registers the window in ``World/windows``
    init(id: WindowId, _ app: AppInfo, parent: Container, weight: CGFloat?, index: Int?) {
        self.windowId = id
        self.app = app
        super.init(parent: parent, weight: weight, index: index)
        check(world.windows.updateValue(self, forKey: id) == nil, "Window \(id) is already registered")
    }

    static func get(byId windowId: WindowId) -> Window? { world.windows[windowId] } // todo make non optional

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(windowId)
    }

    /// `skipClosedWindowsCache` is an optimization for when the closed window definitely doesn't need caching. If you are
    /// unsure, pass `false`
    func garbageCollect(skipClosedWindowsCache: Bool) {
        if world.windows.removeValue(forKey: windowId) == nil {
            return
        }
        if !skipClosedWindowsCache { cacheClosedWindowIfNeeded() }
        guard let parent = destroy()?.parent else { return }
        let deadWindowWorkspace = parent.nodeWorkspace
        let focus = focus
        if let deadWindowWorkspace, deadWindowWorkspace == focus.workspace ||
            deadWindowWorkspace == prevFocusedWorkspace && world.focusStore.prevWorkspaceDate.distance(to: .now) < 1
        {
            switch (parent as? Container)?.kind {
                case .tiling, .floating, .macosHiddenApp, .macosFullscreen:
                    let deadWindowFocus = deadWindowWorkspace.toLiveFocus()
                    _ = setFocus(to: deadWindowFocus)
                    // Guard against "Apple Reminders popup" bug: https://github.com/nikitabobko/AeroSpace/issues/201
                    if focus.windowOrNil?.app.pid != app.pid {
                        // Force focus to fix macOS annoyance with focused apps without windows.
                        //   https://github.com/nikitabobko/AeroSpace/issues/65
                        deadWindowFocus.windowOrNil?.nativeFocus()
                    }
                case .macosPopup, // Don't switch back on popup destruction
                     .macosMinimized, // Don't switch back on minimized windows destruction
                     nil: // A window's parent is always a container
                    break
            }
        }
    }

    func nativeFocus() {
        world.platform.focus(windowId)
    }

    func closeAxWindow() {
        world.platform.close(windowId) // First: the platform finds the window's app through the registered window
        garbageCollect(skipClosedWindowsCache: true)
    }
}

enum LayoutReason: Equatable {
    case standard
    /// macOS made the window fullscreen or minimized, or hid its app. When that state ends, the window goes back to a
    /// container of the kind it left, see normalizeLayoutReason
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
}
