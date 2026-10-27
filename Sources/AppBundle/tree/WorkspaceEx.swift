import Common

extension Workspace {
    /// The root container. nil until a window is bound to the tiling tree or a command writes a root property, see
    /// ``rootTilingContainerCreatingIfNeeded()``. Containers are created on bind, never on read (RB-03, RB-129)
    var existingRootTilingContainer: TilingContainer? {
        singleChild { $0 as? TilingContainer }
    }

    /// For the code that binds a node into the tiling tree or writes a root property. A new root takes the config's layout
    /// and orientation. `auto` is decided by the workspace's monitor at that moment
    func rootTilingContainerCreatingIfNeeded() -> TilingContainer {
        existingRootTilingContainer ?? createChild { TilingContainer(parent: self, newRootOrientation, config.defaultRootContainerLayout) }
    }

    /// The layout and orientation of the root container, or of the one that ``rootTilingContainerCreatingIfNeeded()`` would
    /// create now
    var rootLayout: (layout: Layout, orientation: Orientation) {
        existingRootTilingContainer.map { ($0.layout, $0.orientation) } ?? (config.defaultRootContainerLayout, newRootOrientation)
    }

    private var newRootOrientation: Orientation {
        switch config.defaultRootContainerOrientation {
            case .horizontal: .h
            case .vertical: .v
            case .auto: workspaceMonitor.orientation // todo M2-MON: the workspace's monitor in the monitor snapshot
        }
    }

    /// The windows of the tiling tree in DFS order
    var tilingWindows: [Window] {
        existingRootTilingContainer?.allLeafWindowsRecursive ?? []
    }

    /// Where a new tiling window goes: right after the most recent window if that one is tiling, else at the end of the root
    /// container, which is created if there is none. Unbind a window before it moves there: otherwise it could land next
    /// to itself
    func newTilingWindowSlot() -> (parent: TilingContainer, index: Int) {
        if let (parent, index) = mostRecentWindowRecursive?.tilingSlot { return (parent, index + 1) }
        let root = rootTilingContainerCreatingIfNeeded()
        return (root, root.children.count)
    }

    var floatingWindows: [Window] {
        existingContainer(.floating)?.children.filterIsInstance(of: Window.self) ?? []
    }

    /// The floating, macOS fullscreen or hidden-app container. nil until a window is bound to it, see
    /// ``containerCreatingIfNeeded(_:)``
    func existingContainer(_ kind: ContainerKind) -> Container? {
        singleChild { ($0 as? Container).flatMap { $0.kind == kind ? $0 : nil } }
    }

    /// For the code that binds a window to the floating, macOS fullscreen or hidden-app container
    func containerCreatingIfNeeded(_ kind: ContainerKind) -> Container {
        existingContainer(kind) ?? createChild { Container(kind, parent: self) }
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
        // Binding marks the new container as the most recent child. Restore the previous one: the node that is bound into
        // the container next becomes the most recent one, and a root-writing command doesn't change the MRU order (RB-03)
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
