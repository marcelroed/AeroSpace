@testable import AppBundle
import Common
import Testing

@Suite
struct WorkspaceNameTest {
    /// The reserved names are the words that commands take where they take a workspace name, e.g. `workspace next`
    @Test(arguments: [
        ("focused", "'focused' is a reserved workspace name"),
        ("non-visible", "'non-visible' is a reserved workspace name"),
        ("back_and_forth", "'back_and_forth' is a reserved workspace name"),
        ("next", "'next' is a reserved workspace name"),
        ("workspaces", "'workspaces' is a reserved workspace name"),
        ("mouse", "'mouse' is a reserved workspace name"),
        ("Next", nil), // Case-sensitive
        ("nextt", nil),
        ("", "Empty workspace name is forbidden"),
        ("a,b", "Workspace names are not allowed to contain comma"),
        ("_a", "Workspace names starting with underscore are reserved for future use"),
        ("-a", "Workspace names starting with dash are disallowed"),
        ("a b", "Whitespace characters are forbidden in workspace names"),
        ("_a,b", "Workspace names are not allowed to contain comma"),
    ] as [(String, CmdParseError?)])
    func workspaceNames(name: String, error: CmdParseError?) {
        expectEqual(workspaceName(name).map(\.raw), error.map { .failure($0) } ?? .success(name))
    }

    @Test
    func testParseMonitorDescription() {
        expectEqual(monitorDescription("main"), .success(.main))
        expectEqual(monitorDescription("secondary"), .success(.secondary))
        expectEqual(monitorDescription("2"), .success(.sequenceNumber(2)))
        expectEqual(monitorDescription("Main"), .success(.pattern("Main")))
        expectEqual(monitorDescription(" 1"), .success(.pattern(" 1")))
        expectEqual(monitorDescription("0"), .failure("Monitor sequence numbers uses 1-based indexing. Values less than 1 are illegal"))
        expectEqual(monitorDescription("-1"), .failure("Monitor sequence numbers uses 1-based indexing. Values less than 1 are illegal"))
        expectEqual(monitorDescription(""), .failure("Empty string is an illegal monitor description"))
        expectEqual(monitorDescription("("), .failure("Can't parse '(' regex: expected ')'"))
    }
}

private func workspaceName(_ raw: String) -> Result<WorkspaceName, CmdParseError> {
    Result { () throws(CmdParseError) in try WorkspaceName.parse(raw) }
}

private func monitorDescription(_ raw: String) -> Result<MonitorDescription, CmdParseError> {
    Result { () throws(CmdParseError) in try parseMonitorDescription(raw) }
}
