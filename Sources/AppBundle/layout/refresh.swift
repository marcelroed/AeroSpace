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
    // The screens may disappear at the suspension point above (e.g. display reconfiguration on wake). Then garbage
    // collecting a window would save the closed-windows cache with every workspace on the fake mainMonitorInfo, and
    // restoring it would move them all to the main monitor. Leave the windows to a session that runs with screens
    if !hasScreens { return }
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

enum OptimalHideCorner {
    case bottomLeftCorner, bottomRightCorner
}

func layoutWorkspaces() async throws {
    if !TrayMenuModel.shared.isEnabled {
        for workspace in Workspace.all {
            // No screens: don't lay the windows out against the fake mainMonitorInfo. AeroSpace can't be disabled while there
            // are no screens (EnableCommand), so the windows were unhidden when it was disabled, unless the screens vanished
            // during that session. Then the next `enable off` with screens unhides them. Checked per workspace, because the
            // screens can vanish during an await
            if !hasScreens { return }
            workspace.allLeafWindowsRecursive.forEach { ($0 as! MacWindow).unhideFromCorner() } // todo as!
            try await workspace.layoutWorkspace() // Unhide tiling windows from corner
        }
        return
    }
    let monitors = monitorInfos
    // No screens (e.g., the screens disappeared in the middle of the refresh session). Don't hide windows in the corners of
    // a monitor that doesn't exist
    if monitors.isEmpty { return }
    var monitorToOptimalHideCorner: [CGPoint: OptimalHideCorner] = [:]
    for monitor in monitors {
        let xOff = monitor.width * 0.1
        let yOff = monitor.height * 0.1
        // brc = bottomRightCorner
        let brc1 = monitor.rect.bottomRightCorner + CGPoint(x: 2, y: -yOff)
        let brc2 = monitor.rect.bottomRightCorner + CGPoint(x: -xOff, y: 2)
        let brc3 = monitor.rect.bottomRightCorner + CGPoint(x: 2, y: 2)

        // blc = bottomLeftCorner
        let blc1 = monitor.rect.bottomLeftCorner + CGPoint(x: -2, y: -yOff)
        let blc2 = monitor.rect.bottomLeftCorner + CGPoint(x: xOff, y: 2)
        let blc3 = monitor.rect.bottomLeftCorner + CGPoint(x: -2, y: 2)

        func contains(_ monitor: MonitorInfo, _ point: CGPoint) -> Int { monitor.rect.contains(point) ? 1 : 0 }
        let important = 10

        let corner: OptimalHideCorner =
            monitors.sum { contains($0, blc1) + contains($0, blc2) + important * contains($0, blc3) } <
            monitors.sum { contains($0, brc1) + contains($0, brc2) + important * contains($0, brc3) }
            ? .bottomLeftCorner
            : .bottomRightCorner
        monitorToOptimalHideCorner[monitor.rect.topLeftCorner] = corner
    }

    // to reduce flicker, first unhide visible workspaces, then hide invisible ones
    for monitor in monitors {
        // The screens may also disappear at the suspension points below. Then workspaceMonitor is the fake mainMonitorInfo
        if !hasScreens { return }
        let workspace = monitor.activeWorkspace
        workspace.allLeafWindowsRecursive.forEach { ($0 as! MacWindow).unhideFromCorner() } // todo as!
        try await workspace.layoutWorkspace()
    }
    for workspace in Workspace.all where !workspace.isVisible {
        let corner = monitorToOptimalHideCorner[workspace.workspaceMonitor.rect.topLeftCorner] ?? .bottomRightCorner
        for window in workspace.allLeafWindowsRecursive {
            // Same. hideInCorner would also remember the window position relative to the fake monitor
            if !hasScreens { return }
            try await (window as! MacWindow).hideInCorner(corner) // todo as!
        }
    }
}
