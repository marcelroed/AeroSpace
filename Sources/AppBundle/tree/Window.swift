import AppKit
import Common

final class Window: TreeNode, Hashable {
    nonisolated let windowId: WindowId
    let app: AppInfo
    var lastFloatingSize: CGSize?
    var isFullscreen: Bool = false
    var noOuterGapsInFullscreen: Bool = false
    var layoutReason: LayoutReason = .standard
    /// Set while the window is parked in a corner of its monitor: where it was, relative to its monitor's rect
    private var prevUnhiddenProportionalPositionInsideWorkspaceRect: CGPoint?

    /// Registers the window in ``World/windows``
    init(id: WindowId, _ app: AppInfo, lastFloatingSize: CGSize?, parent: Container, weight: CGFloat?, index: Int?) {
        self.windowId = id
        self.app = app
        self.lastFloatingSize = lastFloatingSize
        super.init(parent: parent, weight: weight, index: index)
        check(world.windows.updateValue(self, forKey: id) == nil, "Window \(id) is already registered")
    }

    static func get(byId windowId: WindowId) -> Window? { world.windows[windowId] } // todo make non optional

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(windowId)
    }

    // skipClosedWindowsCache is an optimization when it's definitely not necessary to cache closed window.
    //                        If you are unsure, it's better to pass `false`
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
        garbageCollect(skipClosedWindowsCache: true)
        world.platform.close(windowId)
    }

    // todo it's part of the window layout and should be moved to layout.swift
    func hideInCorner(_ corner: OptimalHideCorner) async throws(CancellationError) {
        guard let nodeMonitor else { return }
        // Don't accidentally override prevUnhiddenProportionalPositionInsideWorkspaceRect in case of subsequent `hideInCorner` calls
        if !isHiddenInCorner {
            guard let windowRect = try await world.platform.observedRect(windowId) else { return }
            // The window may have closed at the suspension point above
            if !isAlive { return }
            // The screens may disappear at the suspension point above. Leave the window to a session that runs with screens
            if !world.platform.hasScreens { return }
            // Check for isHiddenInCorner for the second time because of the suspension point above
            if !isHiddenInCorner {
                let topLeftCorner = windowRect.topLeftCorner
                let monitorRect = world.monitors.approximation(windowRect.center).rect // Similar to layoutFloatingWindows. Non idempotent
                let absolutePoint = topLeftCorner - monitorRect.topLeftCorner
                prevUnhiddenProportionalPositionInsideWorkspaceRect =
                    CGPoint(x: absolutePoint.x / monitorRect.width, y: absolutePoint.y / monitorRect.height)
                if isFloating {
                    lastFloatingSize = windowRect.size
                }
            }
        }
        world.platform.apply([.park(windowId, ParkTarget(corner: corner, visibleRect: nodeMonitor.visibleRect))])
    }

    func unhideFromCorner() {
        guard let prevUnhiddenProportionalPositionInsideWorkspaceRect else { return }
        guard let nodeWorkspace else { return } // hiding only makes sense for workspace windows

        // Just a small optimization to avoid unnecessary AX calls for non floating windows
        // Tiling windows should be unhidden with layoutWorkspace anyway
        if isFloating {
            let workspaceRect = nodeWorkspace.workspaceMonitor.rect
            var newX = workspaceRect.topLeftX + workspaceRect.width * prevUnhiddenProportionalPositionInsideWorkspaceRect.x
            var newY = workspaceRect.topLeftY + workspaceRect.height * prevUnhiddenProportionalPositionInsideWorkspaceRect.y
            // todo we probably should replace lastFloatingSize with proper floating window sizing
            // https://github.com/nikitabobko/AeroSpace/issues/1519
            let windowWidth = lastFloatingSize?.width ?? 0
            let windowHeight = lastFloatingSize?.height ?? 0
            newX = newX.coerce(in: workspaceRect.minX ... max(workspaceRect.minX, workspaceRect.maxX - windowWidth))
            newY = newY.coerce(in: workspaceRect.minY ... max(workspaceRect.minY, workspaceRect.maxY - windowHeight))

            world.platform.apply([.frame(windowId, topLeft: CGPoint(x: newX, y: newY), size: nil)])
        }

        self.prevUnhiddenProportionalPositionInsideWorkspaceRect = nil
    }

    var isHiddenInCorner: Bool {
        prevUnhiddenProportionalPositionInsideWorkspaceRect != nil
    }
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
}
