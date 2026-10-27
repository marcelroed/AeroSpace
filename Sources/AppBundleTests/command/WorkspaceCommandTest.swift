@testable import AppBundle
import AppKit
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct WorkspaceCommandTest {
    @Test(arguments: [
        ("workspace my mail", "Unknown argument 'mail'"),
        ("workspace 'my mail'", "Whitespace characters are forbidden in workspace names"),
        ("workspace", "Argument '(<workspace-name>|next|prev)' is mandatory"),
        ("workspace --wrap-around W", "--wrap-around requires using (next|prev) argument"),
        ("workspace --auto-back-and-forth next", "--auto-back-and-forth is incompatible with (next|prev)"),
        ("workspace --stdin foo", "--stdin requires using (next|prev) argument"),
        ("workspace -- next", "'next' is a reserved workspace name"),
        ("workspace --", "Argument '(<workspace-name>|next|prev)' is mandatory"),
        ("workspace -- foo --fail-if-noop", "Unknown argument '--fail-if-noop'"),
        ("workspace -- --help", "Workspace names starting with dash are disallowed"),
    ] as [(String, String)])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        expectEqual(output, .fail(error))
    }

    @Test(arguments: workspaceSwitches)
    func focusesWorkspace(_ row: WorkspaceSwitch) async {
        for name in ["a", "b", "c"] {
            _ = Workspace.get(byName: name) // Alive
        }
        #expect(Workspace.get(byName: row.from).focusWorkspace())
        world.focusStore.prevWorkspaceName = row.prev
        let output = await runCmd(row.command, stdin: row.stdin)
        expectEqual(output, row.expected)
        expectEqual(focus.workspace.name, row.to)
    }

    /// The AX work of a switch: each window of the shown workspace gets one frame write, each window of the hidden one is
    /// parked once (a write of its position), and no window gets both. Each placement reads the window's frame first. A
    /// layout without changes only reads
    @Test
    func switchingWorkspacesWritesTheShownWindowsAndParksTheHiddenOnes() async {
        setUpTree("h_tiles(1 2)", workspace: "a")
        setUpTree("h_tiles(3)", workspace: "b")
        for id: WindowId in [1, 2, 3] {
            testWindow(id).rect = rect(0, 0, 100, 100)
        }
        #expect(Workspace.get(byName: "a").focusWorkspace())
        world.platform.apply(placements())
        fake.resetCalls()

        expectEqual(await runCmd("workspace b"), .ok)
        world.platform.apply(placements())

        expectEqual(fake.calls(of: .park).map(\.windowId), [1, 2])
        expectEqual(fake.calls(of: .frame).map(\.windowId), [3, 1, 2]) // 3's tile, then 1 and 2 in their corner
        expectEqual(([1, 2, 3] as [WindowId]).map { fake.isParked($0) }, [true, true, false])
        // The tile is read to compare it with its frame, the parks read where the windows were to put them back there
        expectEqual(fake.calls(of: .axRead).map(\.windowId), [3, 1, 2])
        expectEqual(fake.calls.count, 3 + 2 + 3)

        fake.resetCalls()
        world.platform.apply(placements())
        // The tile is at its frame, and the parked windows are in their corner
        expectEqual(fake.calls.filter { $0.kind != .park }, [.axRead(3), .axRead(1), .axRead(2)])
    }

    /// From the focused workspace `from`, with the previous workspace `prev`, the command focuses the workspace `to`. The
    /// workspaces a, b and c are alive
    nonisolated struct WorkspaceSwitch: Sendable, CustomTestStringConvertible {
        let from: String
        var prev: String? = nil
        let command: String
        var stdin: String = ""
        var expected: CmdOutput = .ok
        let to: String

        var testDescription: String { "'\(command)' from \(from)" + (prev.map { ", prev \($0)" } ?? "") }
    }
}

nonisolated private let workspaceSwitches: [WorkspaceCommandTest.WorkspaceSwitch] = [
    .init(from: "a", command: "workspace b", to: "b"),
    .init(from: "a", command: "workspace a", expected: alreadyFocused, to: "a"),
    .init(from: "a", command: "workspace --fail-if-noop a", expected: .fail(), to: "a"),
    // next and prev without --stdin pick from the workspaces of the monitor
    .init(from: "a", command: "workspace next", to: "b"),
    .init(from: "a", command: "workspace --stdin next", stdin: "a\nb\nc\n", to: "b"),
    .init(from: "b", command: "workspace --stdin prev", stdin: "a\nb\nc\n", to: "a"),
    .init(from: "c", command: "workspace --wrap-around --stdin next", stdin: "a\nb\nc\n", to: "a"),
    .init(from: "a", command: "workspace --wrap-around --stdin prev", stdin: "a\nb\nc\n", to: "c"),
    .init(from: "c", command: "workspace --stdin next", stdin: "a\nb\nc\n", expected: .fail("Reached the end of the supplied workspaces list"), to: "c"),
    .init(from: "a", command: "workspace --stdin prev", stdin: "a\nb\nc\n", expected: .fail("Reached the beginning of the supplied workspaces list"), to: "a"),
    .init(from: "a", command: "workspace --stdin next", expected: .fail("The list of workspaces is empty"), to: "a"),
    // The focused workspace isn't in the list: next and prev land on its first workspace
    .init(from: "z", command: "workspace --stdin next", stdin: "a\nb\nc\n", to: "a"),
    // workspace-back-and-forth, and --auto-back-and-forth when the workspace is focused already (RB-31)
    .init(from: "a", prev: "b", command: "workspace-back-and-forth", to: "b"),
    .init(from: "a", command: "workspace-back-and-forth", expected: .fail("There is no previously focused workspace"), to: "a"),
    .init(from: "a", prev: "b", command: "workspace --auto-back-and-forth a", to: "b"),
    .init(from: "a", prev: "c", command: "workspace --auto-back-and-forth b", to: "b"),
    .init(from: "a", command: "workspace --auto-back-and-forth a", expected: .fail("There is no previously focused workspace"), to: "a"),
]

nonisolated private let alreadyFocused = CmdOutput(stderr: ["Workspace 'a' is already focused. Tip: use --fail-if-noop to exit with non-zero code"])
