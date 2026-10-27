import AppKit
import Common

struct FrozenMonitor: Sendable {
    let topLeftCorner: CGPoint
    let visibleWorkspace: String

    init(_ monitor: MonitorInfo) {
        topLeftCorner = monitor.rect.topLeftCorner
        visibleWorkspace = monitor.activeWorkspace.name
    }
}

struct FrozenWorkspace: Sendable {
    let name: String
    let monitor: FrozenMonitor // todo drop this property, once monitor to workspace assignment migrates to TreeNode
    /// nil: the workspace had no root container
    let rootTilingNode: FrozenContainer?
    /// Followed by the macOS unconventional windows. They are restored as floating and will get fixed by normalizations
    let floatingWindows: [FrozenWindow]

    init(_ workspace: Workspace) {
        name = workspace.name
        monitor = FrozenMonitor(workspace.workspaceMonitor)
        rootTilingNode = workspace.existingRootTilingContainer.map(FrozenContainer.init)
        let kinds: [ContainerKind] = [.floating, .macosHiddenApp, .macosFullscreen]
        floatingWindows = kinds.flatMap { workspace.existingContainer($0)?.children ?? [] }.map { FrozenWindow($0 as! Window) }
    }
}

func cacheClosedWindowIfNeeded() {
    let allWs = Workspace.all
    let allWindowIds: Set<WindowId> = allWs.flatMap(\.allLeafWindowsRecursive).map(\.windowId).toSet()
    if allWindowIds.isSubset(of: world.closedWindowsCache.windowIds) {
        return // already cached
    }
    world.closedWindowsCache = FrozenWorld(
        workspaces: allWs.map { FrozenWorkspace($0) },
        monitors: world.monitors.all.map(FrozenMonitor.init),
        windowIds: allWindowIds,
    )
}

func restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: Window) -> Bool {
    if !world.closedWindowsCache.windowIds.contains(newlyDetectedWindow.windowId) {
        return false
    }
    let topLeftCornerToMonitor = Dictionary(grouping: world.monitors.all, by: { $0.rect.topLeftCorner })

    for frozenWorkspace in world.closedWindowsCache.workspaces {
        let workspace = Workspace.get(byName: frozenWorkspace.name)
        _ = topLeftCornerToMonitor[frozenWorkspace.monitor.topLeftCorner]?
            .singleOrNil()?
            .setActiveWorkspace(workspace)
        for frozenWindow in frozenWorkspace.floatingWindows {
            Window.get(byId: frozenWindow.id)?.move(to: workspace.containerCreatingIfNeeded(.floating))
        }
        let prevRoot = workspace.existingRootTilingContainer // Save prevRoot into a variable to avoid it being garbage collected earlier than needed
        let potentialOrphans = prevRoot?.allLeafWindowsRecursive ?? []
        prevRoot?.destroy()
        if let frozenRoot = frozenWorkspace.rootTilingNode {
            restoreTreeRecursive(frozenContainer: frozenRoot, parent: workspace, index: nil)
        }
        let restoredWindows = workspace.tilingWindows.toSet()
        for window in potentialOrphans where !restoredWindows.contains(window) {
            window.relayoutWindow(on: workspace, as: .window)
        }
    }

    for monitor in world.closedWindowsCache.monitors {
        _ = topLeftCornerToMonitor[monitor.topLeftCorner]?
            .singleOrNil()?
            .setActiveWorkspace(Workspace.get(byName: monitor.visibleWorkspace))
    }
    return true
}

@discardableResult
private func restoreTreeRecursive(frozenContainer: FrozenContainer, parent: TreeNode, index: Int?) -> Bool {
    let container = TilingContainer(
        parent: parent,
        weight: frozenContainer.weight,
        frozenContainer.orientation,
        frozenContainer.layout,
        index: index,
    )

    for (index, child) in frozenContainer.children.enumerated() {
        switch child {
            case .window(let w):
                // Stop the loop if can't find the window, because otherwise all the subsequent windows will have incorrect index
                guard let window = Window.get(byId: w.id) else { return false }
                window.move(to: container, at: index, weight: .value(w.weight))
            case .container(let c):
                // There is no reason to continue
                if !restoreTreeRecursive(frozenContainer: c, parent: container, index: index) { return false }
        }
    }
    return true
}

// Consider the following case:
// 1. Close window
// 2. The previous step lead to caching the whole world
// 3. Change something in the layout
// 4. Lock the screen
// 5. The cache won't be updated because all alive windows are already cached
// 6. Unlock the screen
// 7. The wrong cache is used
//
// That's why we have to reset the cache every time layout changes. The layout can only be changed by running commands
// and with mouse manipulations
func resetClosedWindowsCache() {
    world.closedWindowsCache = FrozenWorld(workspaces: [], monitors: [], windowIds: [])
}
