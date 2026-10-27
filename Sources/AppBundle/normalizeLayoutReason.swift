/// P2's step for the macOS states: a window that macOS made fullscreen or minimized, or whose app is hidden, moves to the
/// container of that state, and moves back when the state ends. A window without facts (gone, or its app didn't answer)
/// stays as it is. `kinds`: the kinds of the windows whose state hid their kind. Such a window ends its state only after an
/// on-screen read of its kind (R2a M1)
func normalizeLayoutReason(_ facts: [WindowId: NativeFacts], _ kinds: [WindowId: DetectedWindow]) {
    for workspace in Workspace.all {
        for window in workspace.allLeafWindowsRecursive {
            normalizeLayoutReason(window, workspace, facts, kinds)
        }
    }
    for case let window as Window in macosMinimizedWindowsContainer.children {
        normalizeLayoutReason(window, focus.workspace, facts, kinds)
    }
}

private func normalizeLayoutReason(
    _ window: Window,
    _ workspace: Workspace,
    _ facts: [WindowId: NativeFacts],
    _ kinds: [WindowId: DetectedWindow],
) {
    guard let parent = window.parent as? Container, let facts = facts[window.windowId] else { return }
    let isMacosWindowOfHiddenApp = !facts.isFullscreen && !facts.isMinimized &&
        !config.automaticallyUnhideMacosHiddenApps && world.platform.isHidden(window.app)
    switch window.layoutReason {
        case .standard:
            switch true {
                case facts.isFullscreen:
                    window.layoutReason = .macos(prevParentKind: parent.kind)
                    window.move(to: workspace.containerCreatingIfNeeded(.macosFullscreen))
                case facts.isMinimized:
                    window.layoutReason = .macos(prevParentKind: parent.kind)
                    window.move(to: macosMinimizedWindowsContainer, weight: .value(1))
                case isMacosWindowOfHiddenApp:
                    window.layoutReason = .macos(prevParentKind: parent.kind)
                    window.move(to: workspace.containerCreatingIfNeeded(.macosHiddenApp))
                default: break
            }
        case .macos(let prevParentKind):
            if !facts.isFullscreen && !facts.isMinimized && !isMacosWindowOfHiddenApp {
                let kind: AxUiElementWindowType? = prevParentKind.hidesKind ? kinds[window.windowId]?.kindOnScreen : .window
                guard let kind else { return }
                exitMacOsNativeUnconventionalState(window: window, prevParentKind: prevParentKind, workspace: workspace, kind: kind)
            }
    }
}

extension LayoutReason {
    /// The window was a popup, or the window's macOS state began while it was in another macOS state: the window's kind
    /// is read again when the state ends
    var hidesKind: Bool {
        switch self {
            case .standard: false
            case .macos(let prevParentKind): prevParentKind.hidesKind
        }
    }
}

extension ContainerKind {
    fileprivate var hidesKind: Bool {
        switch self {
            case .tiling, .floating: false
            case .macosPopup, .macosMinimized, .macosFullscreen, .macosHiddenApp: true
        }
    }
}

/// The commands' variant: reads the kind if the macOS state hid it
func exitMacOsNativeUnconventionalState(window: Window, prevParentKind: ContainerKind, workspace: Workspace) async {
    let kind: AxUiElementWindowType = prevParentKind.hidesKind ? await world.platform.kind(window.windowId) ?? .window : .window
    // The window may have closed or moved, and the workspace may be gone, at the suspension point above
    guard window.isAlive, workspace.isAlive, window.layoutReason == .macos(prevParentKind: prevParentKind) else { return }
    exitMacOsNativeUnconventionalState(window: window, prevParentKind: prevParentKind, workspace: workspace, kind: kind)
}

/// Ends the window's macOS state: it goes back where it was. `kind`: the window's kind, for the states that hid it
func exitMacOsNativeUnconventionalState(
    window: Window,
    prevParentKind: ContainerKind,
    workspace: Workspace,
    kind: AxUiElementWindowType,
) {
    window.layoutReason = .standard
    switch prevParentKind {
        case .floating:
            window.move(to: workspace.containerCreatingIfNeeded(.floating))
        case .tiling:
            window.relayoutWindow(on: workspace, as: .window)
        case .macosPopup: // Since the window was minimized/fullscreened it was mistakenly detected as popup. Relayout the window
            window.relayoutWindow(on: workspace, as: kind)
        case .macosMinimized, .macosFullscreen, .macosHiddenApp: // wtf case, should never be possible. But If encounter it, let's just re-layout window
            window.relayoutWindow(on: workspace, as: kind)
    }
}
