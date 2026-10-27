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
            assertFail(WorkspaceName.parse(name), "'\(name)' is a reserved workspace name")
        }
        assertSucc(WorkspaceName.parse("Next").map(\.raw), "Next")
        assertSucc(WorkspaceName.parse("nextt").map(\.raw), "nextt")
    }

    @Test
    func testIllegalNames() {
        assertFail(WorkspaceName.parse(""), "Empty workspace name is forbidden")
        assertFail(WorkspaceName.parse("a,b"), "Workspace names are not allowed to contain comma")
        assertFail(WorkspaceName.parse("_a"), "Workspace names starting with underscore are reserved for future use")
        assertFail(WorkspaceName.parse("-a"), "Workspace names starting with dash are disallowed")
        assertFail(WorkspaceName.parse("a b"), "Whitespace characters are forbidden in workspace names")
        assertFail(WorkspaceName.parse("_a,b"), "Workspace names are not allowed to contain comma")
    }

    @Test
    func testParseMonitorDescription() {
        assertSucc(parseMonitorDescription("main"), .main)
        assertSucc(parseMonitorDescription("secondary"), .secondary)
        assertSucc(parseMonitorDescription("2"), .sequenceNumber(2))
        assertSucc(parseMonitorDescription("Main"), .pattern("Main")!)
        assertSucc(parseMonitorDescription(" 1"), .pattern(" 1")!)
        assertFail(parseMonitorDescription("0"), "Monitor sequence numbers uses 1-based indexing. Values less than 1 are illegal")
        assertFail(parseMonitorDescription("-1"), "Monitor sequence numbers uses 1-based indexing. Values less than 1 are illegal")
        assertFail(parseMonitorDescription(""), "Empty string is an illegal monitor description")
        assertFail(parseMonitorDescription("("), "Can't parse '(' regex: expected ')'")
    }
}
