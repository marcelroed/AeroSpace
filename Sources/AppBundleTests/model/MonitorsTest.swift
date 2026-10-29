@testable import AppBundle
import Common
import Testing

/// The monitor snapshot of ``World/monitors`` and the workspaces that the monitors show when the snapshot changes
@Suite(.aeroSpaceGlobalState)
struct MonitorsTest {
    /// A monitor that a session holds across an await can be gone after it. Its active workspace used to recurse until the
    /// stack overflowed (812da7fa)
    @Test
    func aMonitorFromAnOlderSnapshotShowsTheWorkspaceOfTheClosestMonitor() {
        updateMonitors([testMonitor, rightTestMonitor])
        updateMonitors([testMonitor])
        expectEqual(rightTestMonitor.activeWorkspace, testMonitor.activeWorkspace)
    }

    @Test
    func aMonitorThatComesBackAtTheSamePlaceGetsItsWorkspaceBack() { // RB-88
        updateMonitors([testMonitor, rightTestMonitor])
        let left = focus.workspace
        let right = Workspace.get(byName: "right")
        #expect(rightTestMonitor.setActiveWorkspace(right))

        updateMonitors([testMonitor]) // The right monitor sleeps
        expectEqual(testMonitor.activeWorkspace, left)
        #expect(!right.isVisible)

        updateMonitors([testMonitor, rightTestMonitor]) // It wakes
        expectEqual(world.monitors.all.map(\.activeWorkspace), [left, right])
    }

    struct StartupCase: Sendable, CustomTestStringConvertible {
        let persistentWorkspaces: [String]
        /// The workspace that `workspace-to-monitor-force-assignment` puts on the secondary monitor
        let onSecondary: String?
        /// 1: ``testMonitor``, 2: and ``rightTestMonitor``
        let monitorCount: Int
        let visible: [String]
        let focus: String
        var testDescription: String { "\(persistentWorkspaces), \(onSecondary ?? "-") on secondary, \(monitorCount) monitor(s)" }
    }

    /// The first snapshot shows the persistent workspaces that belong to each monitor, so the startup creates them first
    @Test(arguments: [
        StartupCase(persistentWorkspaces: ["A", "B", "C"], onSecondary: nil, monitorCount: 1, visible: ["A"], focus: "A"),
        StartupCase(persistentWorkspaces: ["web", "code", "chat"], onSecondary: nil, monitorCount: 1, visible: ["chat"], focus: "chat"),
        StartupCase(persistentWorkspaces: ["1", "2", "web"], onSecondary: "web", monitorCount: 2, visible: ["1", "web"], focus: "1"),
        // Like the default config: 1-9, then letters
        StartupCase(persistentWorkspaces: ["1", "2", "9", "A", "B"], onSecondary: "B", monitorCount: 2, visible: ["1", "B"], focus: "1"),
        StartupCase(persistentWorkspaces: ["1", "2", "9", "A", "B"], onSecondary: nil, monitorCount: 2, visible: ["1", "3"], focus: "1"),
    ] as [StartupCase])
    func theStartupShowsTheWorkspacesThatBelongToEachMonitor(_ row: StartupCase) {
        world.reset(platform: FakePlatform()) // Before the startup: no workspaces, no monitors
        world.config.persistentWorkspaces = .init(row.persistentWorkspaces)
        let forceAssignment: [String: [MonitorDescription]] = row.onSecondary.map { [$0: [.secondary]] } ?? [:]
        world.config.workspaceToMonitorForceAssignment = forceAssignment

        initWorkspaces(Array([testMonitor, rightTestMonitor].prefix(row.monitorCount)))
        expectEqual(world.monitors.all.map(\.activeWorkspace.name), row.visible)
        expectEqual(focus.workspace.name, row.focus)
    }
}
