import AppKit
import Common

/// Which workspace each monitor shows, by the monitors' top-left corners. Part of ``World``
struct MonitorAssignment {
    fileprivate var screenPointToPrevVisibleWorkspace: [CGPoint: String] = [:]
    fileprivate var screenPointToVisibleWorkspace: [CGPoint: Workspace] = [:]
    fileprivate var visibleWorkspaceToScreenPoint: [Workspace: CGPoint] = [:]
}

// The returned workspace must be invisible and it must belong to the requested monitor
func getStubWorkspace(for monitor: MonitorInfo) -> Workspace {
    getStubWorkspace(forPoint: monitor.rect.topLeftCorner)
}

private func getStubWorkspace(forPoint point: CGPoint) -> Workspace {
    if let prev = world.assignment.screenPointToPrevVisibleWorkspace[point].map({ Workspace.get(byName: $0) }),
       !prev.isVisible && prev.workspaceMonitor.rect.topLeftCorner == point && prev.forceAssignedMonitor == nil
    {
        return prev
    }
    if let candidate = Workspace.all
        .first(where: { !$0.isVisible && $0.workspaceMonitor.rect.topLeftCorner == point })
    {
        return candidate
    }
    return (1 ... Int.max).lazy
        .map { Workspace.get(byName: String($0)) }
        .first { $0.isEffectivelyEmpty && !$0.isVisible && !config.persistentWorkspaces.contains($0.name) && $0.forceAssignedMonitor == nil }
        .orDie("Can't create empty workspace")
}

final class Workspace: TreeNode, Hashable, Comparable {
    let name: String
    nonisolated private let nameLogicalSegments: StringLogicalSegments
    /// `assignedMonitorPoint` must be interpreted only when the workspace is invisible
    fileprivate var assignedMonitorPoint: CGPoint? = nil

    private init(_ name: String) {
        self.name = name
        self.nameLogicalSegments = name.toLogicalSegments()
        super.init()
    }

    static var all: [Workspace] {
        world.workspacesByName.values.sorted()
    }

    static func get(byName name: String) -> Workspace {
        if let existing = world.workspacesByName[name] {
            return existing
        } else {
            let workspace = Workspace(name)
            world.workspacesByName[name] = workspace
            return workspace
        }
    }

    nonisolated static func < (lhs: Workspace, rhs: Workspace) -> Bool {
        // Names that differ only in leading zeros ("1", "01") have equal segments. Order them by name to keep the order total.
        // A single pass over the segments, because Workspace.all sorts on every call
        let a = lhs.nameLogicalSegments
        let b = rhs.nameLogicalSegments
        for i in 0 ..< min(a.count, b.count) {
            if a[i] < b[i] { return true }
            if b[i] < a[i] { return false }
        }
        return a.count != b.count ? a.count < b.count : lhs.name < rhs.name
    }

    override func getWeight(_ targetOrientation: Orientation) -> CGFloat {
        workspaceMonitor.visibleRectPaddedByOuterGaps.getDimension(targetOrientation)
    }

    override func setWeight(_ targetOrientation: Orientation, _ newValue: CGFloat) {
        die("It's not possible to change weight of Workspace")
    }

    var description: String {
        let description = [
            ("name", name),
            ("isVisible", String(isVisible)),
            ("isEffectivelyEmpty", String(isEffectivelyEmpty)),
            ("doKeepAlive", String(config.persistentWorkspaces.contains(name))),
        ].map { "\($0.0): \(String(describing: $0.1).singleQuoted)" }.joined(separator: ", ")
        return "Workspace(\(description))"
    }

    static func garbageCollectUnusedWorkspaces() {
        for name in config.persistentWorkspaces {
            _ = get(byName: name) // Make sure that all persistent workspaces are "cached"
        }
        // Remove in place. Reading focus can insert into world.workspacesByName, assigning a filtered copy would drop it
        for (name, workspace) in world.workspacesByName {
            let isUsed = config.persistentWorkspaces.contains(workspace.name) ||
                !workspace.isEffectivelyEmpty ||
                workspace.isVisible ||
                workspace.name == focus.workspace.name
            if !isUsed { world.workspacesByName.removeValue(forKey: name) }
        }
    }

    nonisolated static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        check((lhs === rhs) == (lhs.name == rhs.name), "lhs: \(lhs.name) rhs: \(rhs.name)")
        return lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

extension Workspace {
    var isVisible: Bool { world.assignment.visibleWorkspaceToScreenPoint.keys.contains(self) }
    var workspaceMonitor: MonitorInfo {
        forceAssignedMonitor
            ?? world.assignment.visibleWorkspaceToScreenPoint[self]?.monitorApproximation
            ?? assignedMonitorPoint?.monitorApproximation
            ?? mainMonitorInfo
    }
}

extension MonitorInfo {
    var activeWorkspace: Workspace {
        if let existing = world.assignment.screenPointToVisibleWorkspace[rect.topLeftCorner] {
            return existing
        }
        // What if monitor configuration changed? (frame.origin is changed)
        rearrangeWorkspacesOnMonitors()
        // Normally, the lookup must succeed this time because rearrangeWorkspacesOnMonitors assigns
        // a workspace to every current monitor
        if let existing = world.assignment.screenPointToVisibleWorkspace[rect.topLeftCorner] {
            return existing
        }
        // Monitor configuration data race: self is a stale snapshot, and its rect doesn't match any
        // current monitor (may happen during display sleep/wake reconfiguration). Recursing doesn't
        // converge in this case (it overflows the stack). Fall back to the closest current monitor.
        // The map is empty only if no screen was seen yet (AeroSpace started while there were no screens). Don't read
        // focus then: the lazy initializer of _focus gets here, and reading focus would re-enter it (crash)
        return world.assignment.screenPointToVisibleWorkspace
            .minBy { (rect.topLeftCorner - $0.key).vectorLength }?
            .value
            ?? getStubWorkspace(for: self)
    }

    func setActiveWorkspace(_ workspace: Workspace) -> Bool {
        rect.topLeftCorner.setActiveWorkspace(workspace)
    }
}

func gcMonitors() {
    if world.assignment.screenPointToVisibleWorkspace.count != monitorInfos.count {
        rearrangeWorkspacesOnMonitors()
    }
}

extension CGPoint {
    fileprivate func setActiveWorkspace(_ workspace: Workspace) -> Bool {
        if let forceAssigned = workspace.forceAssignedMonitor, forceAssigned.rect.topLeftCorner != self {
            return false
        }
        world.assignment.show(workspace, at: self)
        workspace.assignedMonitorPoint = self
        return true
    }
}

extension MonitorAssignment {
    fileprivate mutating func show(_ workspace: Workspace, at point: CGPoint) {
        if let prevMonitorPoint = visibleWorkspaceToScreenPoint[workspace] {
            visibleWorkspaceToScreenPoint.removeValue(forKey: workspace)
            screenPointToPrevVisibleWorkspace[prevMonitorPoint] =
                screenPointToVisibleWorkspace.removeValue(forKey: prevMonitorPoint)?.name
        }
        if let prevWorkspace = screenPointToVisibleWorkspace[point] {
            screenPointToPrevVisibleWorkspace[point] = screenPointToVisibleWorkspace.removeValue(forKey: point)?.name
            visibleWorkspaceToScreenPoint.removeValue(forKey: prevWorkspace)
        }
        visibleWorkspaceToScreenPoint[workspace] = point
        screenPointToVisibleWorkspace[point] = workspace
    }
}

private func rearrangeWorkspacesOnMonitors() {
    let newScreens = monitorInfos.map(\.rect.topLeftCorner)
    // No screens (e.g., during display reconfiguration). Keep the current arrangement until the screens come back.
    // Otherwise, every visible workspace is forgotten, and the screens get stub workspaces when they come back
    if newScreens.isEmpty { return }
    var newScreenToOldScreenMapping: [CGPoint: CGPoint] = [:]
    for (oldScreen, _) in world.assignment.screenPointToVisibleWorkspace {
        guard let newScreen = newScreens.minBy({ ($0 - oldScreen).vectorLength }) else { continue }
        if let prevOldScreen = newScreenToOldScreenMapping[newScreen] {
            if (prevOldScreen - newScreen).vectorLength <= (oldScreen - newScreen).vectorLength {
                // newScreen has already been assigned to a closer oldScreen.
                continue
            }
        }
        newScreenToOldScreenMapping[newScreen] = oldScreen
    }

    let oldScreenPointToVisibleWorkspace = world.assignment.screenPointToVisibleWorkspace
    world.assignment.screenPointToVisibleWorkspace = [:]
    world.assignment.visibleWorkspaceToScreenPoint = [:]

    for newScreen in newScreens {
        if let existingVisibleWorkspace = newScreenToOldScreenMapping[newScreen].flatMap({ oldScreenPointToVisibleWorkspace[$0] }),
           newScreen.setActiveWorkspace(existingVisibleWorkspace)
        {
            continue
        }
        let stubWorkspace = getStubWorkspace(forPoint: newScreen)
        check(newScreen.setActiveWorkspace(stubWorkspace),
              "getStubWorkspace generated incompatible stub workspace (\(stubWorkspace.description)) for the monitor (\(newScreen))")
    }
}
