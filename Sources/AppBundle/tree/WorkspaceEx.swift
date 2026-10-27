import Common

extension Workspace {
    /// The root container. Creates it if there is none: then the `auto` orientation is decided by the workspace's monitor at
    /// that moment. Code that only reads uses ``existingRootTilingContainer``, so that reading has no side effects
    var rootTilingContainer: TilingContainer {
        existingRootTilingContainer ?? createChild { TilingContainer(parent: self, newRootOrientation, config.defaultRootContainerLayout) }
    }

    /// nil until something creates the root container, see ``rootTilingContainer``
    var existingRootTilingContainer: TilingContainer? {
        singleChild { $0 as? TilingContainer }
    }

    /// The layout and orientation of the root container, or of the one that ``rootTilingContainer`` would create now
    var rootLayout: (layout: Layout, orientation: Orientation) {
        existingRootTilingContainer.map { ($0.layout, $0.orientation) } ?? (config.defaultRootContainerLayout, newRootOrientation)
    }

    private var newRootOrientation: Orientation {
        switch config.defaultRootContainerOrientation {
            case .horizontal: .h
            case .vertical: .v
            case .auto: workspaceMonitor.orientation
        }
    }

    /// The windows of the tiling tree in DFS order
    var tilingWindows: [Window] {
        existingRootTilingContainer?.allLeafWindowsRecursive ?? []
    }

    /// Where a new tiling window goes: right after the most recent window if that one is tiling, else at the end of the root
    /// container. Unbind a window before it moves there: otherwise it could land next to itself
    var newTilingWindowSlot: (parent: TilingContainer, index: Int) {
        if let (parent, index) = mostRecentWindowRecursive?.tilingSlot { return (parent, index + 1) }
        let root = rootTilingContainer
        return (root, root.children.count)
    }

    var floatingWindows: [Window] {
        floatingWindowsContainer.children.filterIsInstance(of: Window.self)
    }

    var floatingWindowsContainer: Container { specialContainer(.floating) }
    var macOsNativeFullscreenWindowsContainer: Container { specialContainer(.macosFullscreen) }
    var macOsNativeHiddenAppsWindowsContainer: Container { specialContainer(.macosHiddenApp) }

    private func specialContainer(_ kind: ContainerKind) -> Container {
        singleChild { ($0 as? Container).flatMap { $0.kind == kind ? $0 : nil } } ?? createChild { Container(kind, parent: self) }
    }

    /// The only child that `match` accepts. A workspace has at most one root container and one container of each other kind
    private func singleChild<T: TreeNode>(_ match: (TreeNode) -> T?) -> T? {
        var result: T? = nil
        for child in children {
            guard let child = match(child) else { continue }
            check(result == nil, "\(prettyDescription) has more than one \(child.prettyDescription)")
            result = child
        }
        return result
    }

    private func createChild<T: TreeNode>(_ create: () -> T) -> T {
        // Binding marks the new container as the most recent child. Restore the previous one, so that a plain read of a
        // container doesn't make mostRecentWindowRecursive end in the new empty container (RB-03)
        let mostRecentChildBefore = mostRecentChild
        let created = create()
        mostRecentChildBefore?.markAsMostRecentChild()
        return created
    }

    var forceAssignedMonitor: MonitorInfo? {
        guard let monitorDescriptions = config.workspaceToMonitorForceAssignment[name] else { return nil }
        let sortedMonitors = sortedMonitorInfos
        return monitorDescriptions.lazy
            .compactMap { $0.resolveMonitor(sortedMonitors: sortedMonitors) }
            .first
    }
}
