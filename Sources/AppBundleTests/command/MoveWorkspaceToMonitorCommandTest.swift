@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct MoveWorkspaceToMonitorCommandTest {
    @Test(arguments: [
        ("move-workspace-to-monitor --", "Argument '(left|down|up|right|next|prev|<monitor-pattern>)' is mandatory"),
        ("move-workspace-to-monitor --wrap-around 2", "--wrap-around is incompatible with <monitor-pattern> argument"),
    ] as [(String, String)])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        expectEqual(output, .fail(error))
    }

    @Test(arguments: ["--wrap-around next", "--wrap-around left", "main"])
    func singleMonitor_sameMonitor_succeedsSilently(target: String) async {
        let workspace = focus.workspace
        let output = await runCmd("move-workspace-to-monitor \(target)")
        expectEqual(output, .ok)
        expectEqual(focus.workspace, workspace)
        expectEqual(testMonitor.activeWorkspace, workspace)
    }

    @Test
    func twoMonitors_movesTheWorkspaceAndLeavesAStub() async {
        updateMonitors([testMonitor, rightTestMonitor])
        let workspace = focus.workspace
        let output = await runCmd("move-workspace-to-monitor next")
        expectEqual(output, .ok)
        expectEqual(rightTestMonitor.activeWorkspace, workspace)
        #expect(testMonitor.activeWorkspace != workspace)
    }

    /// The monitor of an invisible workspace keeps its visible workspace
    @Test
    func twoMonitors_movesAnInvisibleWorkspace() async {
        updateMonitors([testMonitor, rightTestMonitor])
        let visible = focus.workspace
        let output = await runCmd("move-workspace-to-monitor --workspace other next")
        expectEqual(output, .ok)
        expectEqual(world.monitors.all.map(\.activeWorkspace.name), [visible.name, "other"])
    }
}
