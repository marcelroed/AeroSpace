func normalizeLayoutReason() async throws {
    for workspace in Workspace.all {
        let windows: [Window] = workspace.allLeafWindowsRecursive
        try await _normalizeLayoutReason(workspace: workspace, windows: windows)
    }
    try await _normalizeLayoutReason(workspace: focus.workspace, windows: macosMinimizedWindowsContainer.children.filterIsInstance(of: Window.self))
    try await validateStillPopups()
}

private func validateStillPopups() async throws {
    for node in macosPopupWindowsContainer.children {
        let popup = (node as! MacWindow)
        let windowLevel = getWindowLevel(for: popup.windowId)
        if try await popup.macApp.isWindowHeuristic(popup.windowId.raw, windowLevel, .cancellable) { // todo cache
            // The popup may have closed or moved at the suspension point above
            if popup.parent !== macosPopupWindowsContainer { continue }
            try await popup.relayoutWindow(on: focus.workspace, .cancellable)
            await runOnWindowDetected(ifConventional: popup)
        }
    }
}

private func _normalizeLayoutReason(workspace: Workspace, windows: [Window]) async throws {
    for window in windows {
        guard let parent = window.parent as? Container else { continue }
        let (isMacosFullscreen, isMacosMinimized) = try await window.getMacosFullscreenAndMinimized(.cancellable)
        // The window may have closed or moved, and the workspace may be gone, at the suspension point above
        if window.parent !== parent || !workspace.isAlive { continue }
        let isMacosWindowOfHiddenApp = !isMacosFullscreen && !isMacosMinimized &&
            !config.automaticallyUnhideMacosHiddenApps && window.asMacWindow().macApp.nsApp.isHidden
        switch window.layoutReason {
            case .standard:
                switch true {
                    case isMacosFullscreen:
                        window.layoutReason = .macos(prevParentKind: parent.kind)
                        window.move(to: workspace.containerCreatingIfNeeded(.macosFullscreen))
                    case isMacosMinimized:
                        window.layoutReason = .macos(prevParentKind: parent.kind)
                        window.move(to: macosMinimizedWindowsContainer, weight: .value(1))
                    case isMacosWindowOfHiddenApp:
                        window.layoutReason = .macos(prevParentKind: parent.kind)
                        window.move(to: workspace.containerCreatingIfNeeded(.macosHiddenApp))
                    default: break
                }
            case .macos(let prevParentKind):
                if !isMacosFullscreen && !isMacosMinimized && !isMacosWindowOfHiddenApp {
                    try await exitMacOsNativeUnconventionalState(window: window, prevParentKind: prevParentKind, workspace: workspace, .cancellable)
                }
        }
    }
}

func exitMacOsNativeUnconventionalState(
    window: Window,
    prevParentKind: ContainerKind,
    workspace: Workspace,
    _ cm: CancellationMode,
) async throws {
    window.layoutReason = .standard
    switch prevParentKind {
        case .floating:
            window.move(to: workspace.containerCreatingIfNeeded(.floating))
        case .tiling:
            try await window.relayoutWindow(on: workspace, cm, forceTile: true)
        case .macosPopup: // Since the window was minimized/fullscreened it was mistakenly detected as popup. Relayout the window
            try await window.relayoutWindow(on: workspace, cm)
        case .macosMinimized, .macosFullscreen, .macosHiddenApp: // wtf case, should never be possible. But If encounter it, let's just re-layout window
            try await window.relayoutWindow(on: workspace, cm)
    }
}
