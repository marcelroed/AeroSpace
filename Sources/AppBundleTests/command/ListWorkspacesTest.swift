@testable import AppBundle
import Common
import Foundation
import Testing

@Suite(.aeroSpaceGlobalState)
struct ListWorkspacesTest {
    @Test
    func parse() {
        for command in [
            "list-workspaces --all",
            "list-workspaces --visible --monitor 2",
            "list-workspaces --monitor focused",
            "list-workspaces --all --format %{workspace}",
        ] {
            expectEqual(parseCommand(command).failureOrNil, nil, "\(command)")
        }
        for command in [
            "list-workspaces --all --visible",
            "list-workspaces --focused --visible",
            "list-workspaces --focused --all",
            "list-workspaces --visible",
            "list-workspaces --focused --monitor 2",
        ] {
            #expect(parseCommand(command).failureOrNil != nil, "\(command)")
        }
    }

    @Test(arguments: [
        ("list-workspaces --all --format %{workspace} --count", "Conflicting options: --count, --format"),
        ("list-workspaces --empty", "Mandatory option is not specified (--all|--focused|--monitor)"),
        ("list-workspaces --all --focused --monitor mouse", "Conflicting options: --all, --focused, --monitor"),
    ] as [(String, String)])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        expectEqual(output, .fail(error))
    }

    /// Workspace 'a' has a window, `b` is the tree of workspace 'b' (nil: 'b' doesn't exist). The focused workspace is
    /// the empty "setUpWorkspacesForTests", the only visible one on the single test monitor
    @Test(arguments: [
        // Sorted by logical segments
        ("h_tiles(2)", "list-workspaces --all", ["a", "b", "setUpWorkspacesForTests"]),
        ("h_tiles(2)", "list-workspaces --all --count", ["3"]),
        ("h_tiles(2)", "list-workspaces --monitor all --visible no", ["a", "b"]),
        (nil, "list-workspaces --monitor all --visible", ["setUpWorkspacesForTests"]),
        ("h_tiles()", "list-workspaces --monitor all --empty", ["b", "setUpWorkspacesForTests"]),
        ("h_tiles()", "list-workspaces --monitor all --empty no", ["a"]),
        // --focused is --monitor focused --visible
        (nil, "list-workspaces --focused", ["setUpWorkspacesForTests"]),
        // All workspaces are on the main (focused) monitor
        (nil, "list-workspaces --monitor focused", ["a", "setUpWorkspacesForTests"]),
    ] as [(String?, String, [String])])
    func run(b: String?, command: String, stdout: [String]) async {
        setUpTree("h_tiles(1)", workspace: "a")
        if let b { setUpTree(b, workspace: "b") }
        let output = await runCmd(command)
        expectEqual(output, CmdOutput(stdout: stdout))
    }

    @Test
    func all_namesThatDifferOnlyInLeadingZerosAreOrderedByName() async {
        #expect(Workspace.get(byName: "01") < Workspace.get(byName: "1"))
        #expect(!(Workspace.get(byName: "1") < Workspace.get(byName: "01")))
        setUpTree("h_tiles(1)", workspace: "1")
        setUpTree("h_tiles(2)", workspace: "01")
        setUpTree("h_tiles(3)", workspace: "001")
        let output = await runCmd("list-workspaces --all")
        expectEqual(output, CmdOutput(stdout: ["001", "01", "1", "setUpWorkspacesForTests"]))
    }

    @Test
    func formatVariableOfAnotherObjectFailsWithTheFirstError() async {
        let output = await runCmd("list-workspaces --all --format '%{window-id} %{app-name}'")
        expectEqual(output, .fail(FormatVarExpansionError.unavailable(.windowId, .workspace).description))
    }

    @Test
    func invalidMonitor() async {
        let output = await runCmd("list-workspaces --monitor 99")
        expectEqual(output, .fail("Invalid monitor ID: 99"))
    }

    @Test
    func json() async {
        setUpTree("h_tiles(1)", workspace: "a")
        let expected = JSONEncoder.aeroSpaceDefault.encodeToString([
            ["workspace": "a"],
            ["workspace": "setUpWorkspacesForTests"],
        ])
        let output = await runCmd("list-workspaces --all --format '%{workspace}' --json")
        expectEqual(output, CmdOutput(stdout: [expected.orDie()]))
    }
}
