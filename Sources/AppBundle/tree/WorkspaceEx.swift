import Common

extension Workspace {
    @MainActor var rootTilingContainer: TilingContainer {
        singleChild(TilingContainer.self, dieMessage: "Workspace must contain zero or one tiling container as its child") {
            let orientation: Orientation = switch config.defaultRootContainerOrientation {
                case .horizontal: .h
                case .vertical: .v
                case .auto: workspaceMonitor.then { $0.width >= $0.height } ? .h : .v
            }
            return TilingContainer(parent: self, adaptiveWeight: 1, orientation, config.defaultRootContainerLayout, index: INDEX_BIND_LAST)
        }
    }

    @MainActor
    var floatingWindows: [Window] {
        floatingWindowsContainer.children.filterIsInstance(of: Window.self)
    }

    @MainActor
    var floatingWindowsContainer: FloatingWindowsContainer {
        singleChild(FloatingWindowsContainer.self, dieMessage: "Workspace must contain zero or one FloatingWindowsContainer") {
            FloatingWindowsContainer(parent: self)
        }
    }

    @MainActor var macOsNativeFullscreenWindowsContainer: MacosFullscreenWindowsContainer {
        singleChild(MacosFullscreenWindowsContainer.self, dieMessage: "Workspace must contain zero or one MacosFullscreenWindowsContainer") {
            MacosFullscreenWindowsContainer(parent: self)
        }
    }

    @MainActor var macOsNativeHiddenAppsWindowsContainer: MacosHiddenAppsWindowsContainer {
        singleChild(MacosHiddenAppsWindowsContainer.self, dieMessage: "Workspace must contain zero or one MacosHiddenAppsWindowsContainer") {
            MacosHiddenAppsWindowsContainer(parent: self)
        }
    }

    /// Returns the only child of type `T`, or creates it if there is none
    private func singleChild<T: TreeNode>(_: T.Type, dieMessage: String, orCreate create: () -> T) -> T {
        var result: T? = nil
        for child in children {
            guard let child = child as? T else { continue }
            if result != nil { die(dieMessage) }
            result = child
        }
        return result ?? create()
    }

    @MainActor var forceAssignedMonitor: MonitorInfo? {
        guard let monitorDescriptions = config.workspaceToMonitorForceAssignment[name] else { return nil }
        let sortedMonitors = sortedMonitorInfos
        return monitorDescriptions.lazy
            .compactMap { $0.resolveMonitor(sortedMonitors: sortedMonitors) }
            .first
    }
}
