@testable import AppBundle
import Common
import Foundation
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct ListWorkspacesTest: AeroSpaceTestSuite {
    @Test
    func testParse() {
        assertNotNil(parseCommand("list-workspaces --all").cmdOrNil)
        assertNil(parseCommand("list-workspaces --all --visible").cmdOrNil)
        assertNil(parseCommand("list-workspaces --focused --visible").cmdOrNil)
        assertNil(parseCommand("list-workspaces --focused --all").cmdOrNil)
        assertNil(parseCommand("list-workspaces --visible").cmdOrNil)
        assertNotNil(parseCommand("list-workspaces --visible --monitor 2").cmdOrNil)
        assertNotNil(parseCommand("list-workspaces --monitor focused").cmdOrNil)
        assertNil(parseCommand("list-workspaces --focused --monitor 2").cmdOrNil)
        assertNotNil(parseCommand("list-workspaces --all --format %{workspace}").cmdOrNil)
        assertEquals(parseCommand("list-workspaces --all --format %{workspace} --count").errorOrNil, "ERROR: Conflicting options: --count, --format")
        assertEquals(parseCommand("list-workspaces --empty").errorOrNil, "ERROR: Mandatory option is not specified (--all|--focused|--monitor)")
        assertEquals(parseCommand("list-workspaces --all --focused --monitor mouse").errorOrNil, "ERROR: Conflicting options: --all, --focused, --monitor")
    }

    @Test
    func testRunAll() async {
        TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        TestWindow.new(id: 2, parent: Workspace.get(byName: "b").rootTilingContainer)
        // Initial focused workspace "setUpWorkspacesForTests" is included; sort uses logical segments.
        await assertRun("list-workspaces --all", exitCode: 0, stdout: ["a", "b", "setUpWorkspacesForTests"], stderr: [])
    }

    @Test
    func testRunAll_namesThatDifferOnlyInLeadingZerosAreOrderedByName() async {
        #expect(Workspace.get(byName: "01") < Workspace.get(byName: "1"))
        #expect(!(Workspace.get(byName: "1") < Workspace.get(byName: "01")))
        TestWindow.new(id: 1, parent: Workspace.get(byName: "1").rootTilingContainer)
        TestWindow.new(id: 2, parent: Workspace.get(byName: "01").rootTilingContainer)
        TestWindow.new(id: 3, parent: Workspace.get(byName: "001").rootTilingContainer)
        await assertRun("list-workspaces --all", exitCode: 0, stdout: ["001", "01", "1", "setUpWorkspacesForTests"])
    }

    @Test
    func testRunVisible() async {
        TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        // Only the focused workspace is visible after setUp on the single test monitor.
        await assertRun("list-workspaces --monitor all --visible", exitCode: 0, stdout: ["setUpWorkspacesForTests"])
    }

    @Test
    func testRunInvisible() async {
        TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        TestWindow.new(id: 2, parent: Workspace.get(byName: "b").rootTilingContainer)
        await assertRun("list-workspaces --monitor all --visible no", exitCode: 0, stdout: ["a", "b"])
    }

    @Test
    func testRunEmpty() async {
        TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        _ = Workspace.get(byName: "b") // empty (no windows)
        await assertRun("list-workspaces --monitor all --empty", exitCode: 0, stdout: ["b", "setUpWorkspacesForTests"])
    }

    @Test
    func testRunNonEmpty() async {
        TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        _ = Workspace.get(byName: "b") // empty
        await assertRun("list-workspaces --monitor all --empty no", exitCode: 0, stdout: ["a"])
    }

    @Test
    func testRunFocusedAlias() async {
        // The initial focused workspace is "setUpWorkspacesForTests" (visible on the focused monitor).
        TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        // --focused expands to --monitor focused --visible true.
        await assertRun("list-workspaces --focused", exitCode: 0, stdout: ["setUpWorkspacesForTests"])
    }

    @Test
    func testRunMonitorFocused() async {
        TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        // All workspaces default to the main (focused) monitor in tests.
        await assertRun("list-workspaces --monitor focused", exitCode: 0, stdout: ["a", "setUpWorkspacesForTests"])
    }

    @Test
    func testRunInvalidMonitor() async {
        await assertRun("list-workspaces --monitor 99", exitCode: 2, stdout: [], stderr: ["Invalid monitor ID: 99"])
    }

    @Test
    func testRunCount() async {
        TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        TestWindow.new(id: 2, parent: Workspace.get(byName: "b").rootTilingContainer)
        await assertRun("list-workspaces --all --count", exitCode: 0, stdout: ["3"])
    }

    @Test
    func testRunJson() async {
        TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        let expected = JSONEncoder.aeroSpaceDefault.encodeToString([
            ["workspace": "a"],
            ["workspace": "setUpWorkspacesForTests"],
        ])
        await assertRun("list-workspaces --all --format '%{workspace}' --json", exitCode: 0, stdout: [expected.orDie()])
    }
}
