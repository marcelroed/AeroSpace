import AppKit
import Common

/// Which workspace each monitor of ``World/monitors`` shows. Part of ``World``
struct MonitorAssignment {
    /// `visible[i]` is on `world.monitors.all[i]`: ``updateMonitors(_:)`` replaces the monitors and rearranges this in one
    /// step. Empty only before the first snapshot
    fileprivate var visible: [Workspace] = []
    /// The workspace that each monitor showed before the last ``MonitorInfo/setActiveWorkspace(_:)`` on it, by the
    /// monitor's top-left corner. The first choice for the monitor's stub workspace
    fileprivate var prevVisible: [CGPoint: String] = [:]
}

final class Workspace: TreeNode, Hashable, Comparable {
    let name: String
    nonisolated private let nameLogicalSegments: StringLogicalSegments
    /// The top-left corner of the monitor that the workspace is visible on, or was visible on last
    fileprivate var assignedMonitorPoint: CGPoint? = nil

    private init(_ name: String) {
        self.name = name
        self.nameLogicalSegments = name.toLogicalSegments()
        super.init()
    }

    static var all: [Workspace] {
        if let sorted = world.sortedWorkspaces { return sorted }
        let sorted = world.workspacesByName.values.sorted()
        world.sortedWorkspaces = sorted
        return sorted
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
        // A single pass over the segments
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

    /// Creates the persistent workspaces that don't exist yet
    static func ensurePersistentWorkspaces() {
        for name in config.persistentWorkspaces {
            _ = get(byName: name)
        }
    }

    static func garbageCollectUnusedWorkspaces() {
        ensurePersistentWorkspaces()
        // Remove in place. Reading focus can insert into world.workspacesByName, assigning a filtered copy would drop it
        for (name, workspace) in world.workspacesByName {
            let isUsed = config.persistentWorkspaces.contains(workspace.name) ||
                !workspace.isEffectivelyEmpty ||
                workspace.isVisible ||
                workspace.name == focus.workspace.name
            if !isUsed { world.workspacesByName.removeValue(forKey: name)?.destroy() }
        }
    }

    /// Identity. `workspacesByName` keeps the names of live workspaces unique, but a workspace held across an await can be
    /// garbage collected and replaced by a new one with the same name: the two are different workspaces
    nonisolated static func == (lhs: Workspace, rhs: Workspace) -> Bool { lhs === rhs }

    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

extension Workspace {
    var isVisible: Bool { world.assignment.visible.contains(self) }

    /// The monitor that the workspace is visible on, or was visible on last (the closest one if that monitor is gone), or the
    /// main monitor. Force assignment overrides them
    var workspaceMonitor: MonitorInfo {
        forceAssignedMonitor ?? assignedMonitorPoint.map(world.monitors.approximation) ?? world.monitors.main
    }

    /// Force assignment allows the workspace on `world.monitors.all[index]`
    fileprivate func isAllowed(onMonitorAt index: Int) -> Bool {
        forceAssignedMonitor.map { world.monitors.index(of: $0) == index } ?? true
    }
}

extension MonitorInfo {
    /// Total: a monitor from an older snapshot (held across an await) gets the workspace of the closest monitor (812da7fa)
    var activeWorkspace: Workspace { world.assignment.visible[world.monitors.index(of: self)] }

    /// Shows `workspace` on this monitor. If it was visible on another monitor, that one gets a stub workspace. false if
    /// force assignment doesn't allow `workspace` on this monitor
    func setActiveWorkspace(_ workspace: Workspace) -> Bool {
        let index = world.monitors.index(of: self)
        if !workspace.isAllowed(onMonitorAt: index) { return false }
        let prevIndex = world.assignment.visible.firstIndex(of: workspace)
        show(workspace, onMonitorAt: index)
        if let prevIndex, prevIndex != index {
            show(stubWorkspace(forMonitorAt: prevIndex, excluding: world.assignment.visible), onMonitorAt: prevIndex)
        }
        return true
    }
}

/// Takes the snapshot of the monitors (`monitors`: tests only). If the monitors moved, every monitor keeps the workspace of
/// the closest old monitor, and the other monitors get stub workspaces. While there are no screens, the last monitors and
/// their workspaces stay. Called at the start of every session. Returns whether there are screens
@discardableResult
func updateMonitors(_ monitors: [MonitorInfo] = world.platform.monitors()) -> Bool {
    let old = world.monitors
    let new = Monitors(monitors) ?? old.withoutScreens
    world.monitors = new
    if world.assignment.visible.count != new.all.count || !new.hasSameCorners(as: old) {
        rearrangeWorkspaces(from: old)
    }
    return new.hasScreens
}

/// Each monitor of the old snapshot hands its workspace to the closest new monitor. A new monitor that is the closest to
/// several old ones takes the workspace of the closest old one. Force assignment can refuse it, then the monitor gets a stub
private func rearrangeWorkspaces(from old: Monitors) {
    let monitors = world.monitors
    let oldVisible = zip(old.all, world.assignment.visible)
    var closest: [(workspace: Workspace, distance: CGFloat)?] = Array(repeating: nil, count: monitors.all.count)
    for (oldMonitor, workspace) in oldVisible {
        let index = monitors.index(of: oldMonitor)
        let distance = (monitors.all[index].rect.topLeftCorner - oldMonitor.rect.topLeftCorner).vectorLength
        if let closer = closest[index], closer.distance <= distance { continue }
        closest[index] = (workspace, distance)
    }
    let kept: [Workspace?] = closest.enumerated().map { index, closest in
        closest.flatMap { $0.workspace.isAllowed(onMonitorAt: index) ? $0.workspace : nil }
    }
    let taken = kept.compactMap { $0 }
    var visible: [Workspace] = []
    for (index, workspace) in kept.enumerated() {
        visible.append(workspace ?? stubWorkspace(forMonitorAt: index, excluding: taken + visible))
    }
    world.assignment.visible = visible
    for (monitor, workspace) in zip(monitors.all, visible) {
        workspace.assignedMonitorPoint = monitor.rect.topLeftCorner
    }
    // A monitor that comes back at the same place gets its workspace back (e.g. monitors that wake one after another, RB-88)
    for (oldMonitor, workspace) in oldVisible where !visible.contains(workspace) {
        world.assignment.prevVisible[oldMonitor.rect.topLeftCorner] = workspace.name
    }
}

/// Doesn't check force assignment
private func show(_ workspace: Workspace, onMonitorAt index: Int) {
    let corner = world.monitors.all[index].rect.topLeftCorner
    world.assignment.prevVisible[corner] = world.assignment.visible[index].name
    world.assignment.visible[index] = workspace
    workspace.assignedMonitorPoint = corner
}

/// A workspace for `world.monitors.all[index]` that isn't in `taken`, and that force assignment allows there: the one that
/// the monitor showed before, else the first one that belongs to the monitor, else the first empty numbered one
private func stubWorkspace(forMonitorAt index: Int, excluding taken: [Workspace]) -> Workspace {
    let corner = world.monitors.all[index].rect.topLeftCorner
    let belongsToMonitor = { (workspace: Workspace) -> Bool in
        !taken.contains(workspace) && workspace.workspaceMonitor.rect.topLeftCorner == corner
    }
    if let prev = world.assignment.prevVisible[corner].map({ Workspace.get(byName: $0) }), belongsToMonitor(prev) {
        return prev
    }
    if let workspace = Workspace.all.first(where: belongsToMonitor) {
        return workspace
    }
    for number in 1 ... Int.max {
        let workspace = Workspace.get(byName: String(number))
        if !taken.contains(workspace) && workspace.isEffectivelyEmpty && !config.persistentWorkspaces.contains(workspace.name) &&
            workspace.forceAssignedMonitor == nil
        {
            return workspace
        }
    }
    die("Can't create empty workspace")
}
