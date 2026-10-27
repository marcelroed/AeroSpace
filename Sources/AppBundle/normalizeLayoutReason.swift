func normalizeLayoutReason() async throws(CancellationError) {
    for workspace in Workspace.all {
        let windows: [Window] = workspace.allLeafWindowsRecursive
        try await _normalizeLayoutReason(workspace: workspace, windows: windows)
    }
    try await _normalizeLayoutReason(workspace: focus.workspace, windows: macosMinimizedWindowsContainer.children.filterIsInstance(of: Window.self))
    try await validateStillPopups()
}

private func validateStillPopups() async throws(CancellationError) {
    for case let popup as Window in macosPopupWindowsContainer.children {
        guard let kind = try await world.platform.classify(popup.windowId), kind != .popup else { continue } // todo cache
        // The popup may have closed or moved at the suspension point above
        if popup.parent !== macosPopupWindowsContainer { continue }
        popup.relayoutWindow(on: focus.workspace, as: kind)
        await runOnWindowDetected(ifConventional: popup)
    }
}

private func _normalizeLayoutReason(workspace: Workspace, windows: [Window]) async throws(CancellationError) {
    for window in windows {
        guard let parent = window.parent as? Container else { continue }
        let facts = try await world.platform.nativeFacts(window.windowId)
        let isMacosFullscreen = facts?.isFullscreen == true
        let isMacosMinimized = facts?.isMinimized == true
        // The window may have closed or moved, and the workspace may be gone, at the suspension point above
        if window.parent !== parent || !workspace.isAlive { continue }
        let isMacosWindowOfHiddenApp = !isMacosFullscreen && !isMacosMinimized &&
            !config.automaticallyUnhideMacosHiddenApps && world.platform.isHidden(window.app)
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
                    await exitMacOsNativeUnconventionalState(window: window, prevParentKind: prevParentKind, workspace: workspace)
                }
        }
    }
}

func exitMacOsNativeUnconventionalState(
    window: Window,
    prevParentKind: ContainerKind,
    workspace: Workspace,
) async {
    window.layoutReason = .standard
    switch prevParentKind {
        case .floating:
            window.move(to: workspace.containerCreatingIfNeeded(.floating))
        case .tiling:
            window.relayoutWindow(on: workspace, as: .window)
        case .macosPopup: // Since the window was minimized/fullscreened it was mistakenly detected as popup. Relayout the window
            await window.relayoutWindow(on: workspace)
        case .macosMinimized, .macosFullscreen, .macosHiddenApp: // wtf case, should never be possible. But If encounter it, let's just re-layout window
            await window.relayoutWindow(on: workspace)
    }
}
