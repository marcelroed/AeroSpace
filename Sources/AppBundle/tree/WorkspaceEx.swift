import Common

extension Workspace {
    var rootTilingContainer: TilingContainer {
        singleChild({ $0 as? TilingContainer }, dieMessage: "Workspace must contain zero or one tiling container as its child") {
            let orientation: Orientation = switch config.defaultRootContainerOrientation {
                case .horizontal: .h
                case .vertical: .v
                case .auto: workspaceMonitor.then { $0.width >= $0.height } ? .h : .v
            }
            return TilingContainer(parent: self, orientation, config.defaultRootContainerLayout)
        }
    }

    var floatingWindows: [Window] {
        floatingWindowsContainer.children.filterIsInstance(of: Window.self)
    }

    var floatingWindowsContainer: Container { specialContainer(.floating) }
    var macOsNativeFullscreenWindowsContainer: Container { specialContainer(.macosFullscreen) }
    var macOsNativeHiddenAppsWindowsContainer: Container { specialContainer(.macosHiddenApp) }

    private func specialContainer(_ kind: ContainerKind) -> Container {
        singleChild(
            { ($0 as? Container)?.takeIf { $0.kind == kind } },
            dieMessage: "Workspace must contain zero or one \(kind) container",
        ) { Container(kind, parent: self) }
    }

    /// Returns the only child that `match` accepts, or creates it if there is none
    private func singleChild<T: TreeNode>(
        _ match: (TreeNode) -> T?,
        dieMessage: @autoclosure () -> String,
        file: StaticString = #fileID,
        line: Int = #line,
        column: Int = #column,
        function: String = #function,
        orCreate create: () -> T,
    ) -> T {
        var result: T? = nil
        for child in children {
            guard let child = match(child) else { continue }
            if result != nil { die(dieMessage(), file: file, line: line, column: column, function: function) }
            result = child
        }
        if let result { return result }
        // bind() marks the new container as the most recent child. Restore the previous one, so that a plain read
        // doesn't make mostRecentWindowRecursive end in the new empty container
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
