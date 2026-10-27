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
            #expect(workspaceName(name) == .failure("'\(name)' is a reserved workspace name"))
        }
        #expect(workspaceName("Next").map(\.raw) == .success("Next"))
        #expect(workspaceName("nextt").map(\.raw) == .success("nextt"))
    }

    @Test
    func testIllegalNames() {
        #expect(workspaceName("") == .failure("Empty workspace name is forbidden"))
        #expect(workspaceName("a,b") == .failure("Workspace names are not allowed to contain comma"))
        #expect(workspaceName("_a") == .failure("Workspace names starting with underscore are reserved for future use"))
        #expect(workspaceName("-a") == .failure("Workspace names starting with dash are disallowed"))
        #expect(workspaceName("a b") == .failure("Whitespace characters are forbidden in workspace names"))
        #expect(workspaceName("_a,b") == .failure("Workspace names are not allowed to contain comma"))
    }

    @Test
    func testParseMonitorDescription() {
        #expect(monitorDescription("main") == .success(.main))
        #expect(monitorDescription("secondary") == .success(.secondary))
        #expect(monitorDescription("2") == .success(.sequenceNumber(2)))
        #expect(monitorDescription("Main") == .success(.pattern("Main")))
        #expect(monitorDescription(" 1") == .success(.pattern(" 1")))
        #expect(monitorDescription("0") == .failure("Monitor sequence numbers uses 1-based indexing. Values less than 1 are illegal"))
        #expect(monitorDescription("-1") == .failure("Monitor sequence numbers uses 1-based indexing. Values less than 1 are illegal"))
        #expect(monitorDescription("") == .failure("Empty string is an illegal monitor description"))
        #expect(monitorDescription("(") == .failure("Can't parse '(' regex: expected ')'"))
    }
}

private func workspaceName(_ raw: String) -> Result<WorkspaceName, CmdParseError> {
    Result { () throws(CmdParseError) in try WorkspaceName.parse(raw) }
}

private func monitorDescription(_ raw: String) -> Result<MonitorDescription, CmdParseError> {
    Result { () throws(CmdParseError) in try parseMonitorDescription(raw) }
}
