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
func refresh() async throws {
    // Garbage collect terminated apps and windows before working with all windows
    let mapping = try await MacApp.refreshAllAndGetAliveWindowIds(frontmostAppBundleId: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    // The screens may disappear at the suspension point above (e.g. display reconfiguration on wake). Leave the windows to a
    // session that runs with screens. todo M2-REC: P1's re-check of `platform.monitors()` replaces this (RB-01)
    if !liveHasScreens() { return }
    let aliveWindowIds = mapping.values.flatMap { $0 }.toSet()

    for window in MacWindow.allWindows {
        if !aliveWindowIds.contains(window.windowId) {
            window.garbageCollect(skipClosedWindowsCache: false)
        }
    }
    for (app, windowIds) in mapping {
        for windowId in windowIds {
            try await MacWindow.getOrRegister(windowId: windowId, macApp: app)
        }
    }

    // Garbage collect workspaces after apps, because workspaces contain apps.
    Workspace.garbageCollectUnusedWorkspaces()
}

func layoutWorkspaces() async throws {
    if !world.isEnabled {
        for workspace in Workspace.all {
            // No screens: wait for them. AeroSpace can't be disabled while there are no screens (EnableCommand), so the
            // windows were unhidden when it was disabled, unless the screens vanished during that session. Then the next
            // `enable off` with screens unhides them. Checked per workspace, because the screens can vanish during an await
            if !liveHasScreens() { return }
            workspace.allLeafWindowsRecursive.forEach { ($0 as! MacWindow).unhideFromCorner() } // todo as!
            try await workspace.layoutWorkspace() // Unhide tiling windows from corner
        }
        return
    }
    let monitors = world.monitors
    // No screens (e.g., the screens disappeared in the middle of the refresh session). Don't hide windows in the corners of
    // a monitor that doesn't exist
    if !liveHasScreens() { return }

    // to reduce flicker, first unhide visible workspaces, then hide invisible ones
    for monitor in monitors.all {
        // The screens may also disappear at the suspension points below
        if !liveHasScreens() { return }
        let workspace = monitor.activeWorkspace
        workspace.allLeafWindowsRecursive.forEach { ($0 as! MacWindow).unhideFromCorner() } // todo as!
        try await workspace.layoutWorkspace()
    }
    for workspace in Workspace.all where !workspace.isVisible {
        let corner = world.monitors.hideCorner(of: workspace.workspaceMonitor)
        for window in workspace.allLeafWindowsRecursive {
            // Same
            if !liveHasScreens() { return }
            try await (window as! MacWindow).hideInCorner(corner) // todo as!
        }
    }
}
