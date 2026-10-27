import AppKit
import Common

func refreshModel_nonCancellable() async {
    if refreshSessionEvent?.isFocusFollowsMouse == true {
        await checkOnFocusChangedCallbacks_nonCancellable()
    } else {
        Workspace.garbageCollectUnusedWorkspaces()
        await checkOnFocusChangedCallbacks_nonCancellable()
        // Can't do it only for visible workspace because most of the commands support --window-id and --workspace flags
        for workspace in Workspace.all {
            workspace.normalizeContainers()
        }
    }
}

/// Garbage collects the windows of terminated apps and closed windows, then registers the new ones
func refresh() async throws(CancellationError) {
    // Garbage collect terminated apps and windows before working with all windows
    let apps = try await world.platform.listWindows()
    // The screens may disappear at the suspension point above (e.g. display reconfiguration on wake). Leave the windows to a
    // session that runs with screens. todo M2-REC: P1's re-check of `platform.monitors()` replaces this (RB-01)
    if !world.platform.hasScreens { return }
    var aliveWindowIds: Set<WindowId> = []
    for case .listed(_, let ids) in apps { aliveWindowIds.formUnion(ids) }

    for window in Array(world.windows.values) {
        if !aliveWindowIds.contains(window.windowId) {
            window.garbageCollect(skipClosedWindowsCache: false)
        }
    }
    for case .listed(let app, let windowIds) in apps {
        for windowId in windowIds {
            try await registerWindow(windowId, app)
        }
    }

    // Garbage collect workspaces after apps, because workspaces contain apps.
    Workspace.garbageCollectUnusedWorkspaces()
}

/// Lays out the visible workspaces, then parks the windows of the others (to reduce flicker), in one batch
func layoutWorkspaces() throws(CancellationError) {
    try checkCancellation()
    var placements: [Placement] = []
    if !world.isEnabled {
        // No screens: wait for them. AeroSpace can't be disabled while there are no screens (EnableCommand), so the
        // windows were unhidden when it was disabled, unless the screens vanished during that session. Then the next
        // `enable off` with screens unhides them
        if !world.platform.hasScreens { return }
        for workspace in Workspace.all {
            placements += workspace.layoutPlacements() // Unparks every window
        }
        world.platform.apply(placements)
        return
    }
    let monitors = world.monitors
    // No screens (e.g., the screens disappeared in the middle of the refresh session). Don't hide windows in the corners of
    // a monitor that doesn't exist
    if !world.platform.hasScreens { return }

    for monitor in monitors.all {
        placements += monitor.activeWorkspace.layoutPlacements()
    }
    for workspace in Workspace.all where !workspace.isVisible {
        let monitor = workspace.workspaceMonitor
        let corner = monitors.hideCorner(of: monitor)
        for window in workspace.allLeafWindowsRecursive {
            let target = ParkTarget(corner: corner, monitor: monitor, monitors: monitors.all, isFloating: window.isFloating)
            placements.append(.park(window.windowId, target))
        }
    }
    world.platform.apply(placements)
}
