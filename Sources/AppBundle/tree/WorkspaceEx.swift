import Common

extension Workspace {
    var rootTilingContainer: TilingContainer {
        singleChild(TilingContainer.self, dieMessage: "Workspace must contain zero or one tiling container as its child") {
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

    var floatingWindowsContainer: FloatingWindowsContainer {
        singleChild(FloatingWindowsContainer.self, dieMessage: "Workspace must contain zero or one FloatingWindowsContainer") {
            FloatingWindowsContainer(parent: self)
        }
    }

    var macOsNativeFullscreenWindowsContainer: MacosFullscreenWindowsContainer {
        singleChild(MacosFullscreenWindowsContainer.self, dieMessage: "Workspace must contain zero or one MacosFullscreenWindowsContainer") {
            MacosFullscreenWindowsContainer(parent: self)
        }
    }

    var macOsNativeHiddenAppsWindowsContainer: MacosHiddenAppsWindowsContainer {
        singleChild(MacosHiddenAppsWindowsContainer.self, dieMessage: "Workspace must contain zero or one MacosHiddenAppsWindowsContainer") {
            MacosHiddenAppsWindowsContainer(parent: self)
        }
    }

    /// Returns the only child of type `T`, or creates it if there is none
    private func singleChild<T: TreeNode>(
        _: T.Type,
        dieMessage: String,
        file: StaticString = #fileID,
        line: Int = #line,
        column: Int = #column,
        function: String = #function,
        orCreate create: () -> T,
    ) -> T {
        var result: T? = nil
        for child in children {
            guard let child = child as? T else { continue }
            if result != nil { die(dieMessage, file: file, line: line, column: column, function: function) }
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
