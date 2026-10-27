@testable import AppBundle
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
}
