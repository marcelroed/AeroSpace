@testable import AppBundle
import Common
import Testing

@Suite
struct WorkspaceNameTest {
    @Test
    func testReservedNames() {
        let reserved = [
            "focused", "non-focused", "visible", "invisible", "non-visible", "active", "non-active", "inactive",
            "back-and-forth", "back_and_forth", "previous", "prev", "next", "monitor", "workspace", "monitors", "workspaces",
            "all", "none", "mouse", "target",
        ]
        for name in reserved {
            expectEqual(workspaceName(name), .failure("'\(name)' is a reserved workspace name"))
        }
        expectEqual(workspaceName("Next").map(\.raw), .success("Next"))
        expectEqual(workspaceName("nextt").map(\.raw), .success("nextt"))
    }

    @Test
    func testIllegalNames() {
        expectEqual(workspaceName(""), .failure("Empty workspace name is forbidden"))
        expectEqual(workspaceName("a,b"), .failure("Workspace names are not allowed to contain comma"))
        expectEqual(workspaceName("_a"), .failure("Workspace names starting with underscore are reserved for future use"))
        expectEqual(workspaceName("-a"), .failure("Workspace names starting with dash are disallowed"))
        expectEqual(workspaceName("a b"), .failure("Whitespace characters are forbidden in workspace names"))
        expectEqual(workspaceName("_a,b"), .failure("Workspace names are not allowed to contain comma"))
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
