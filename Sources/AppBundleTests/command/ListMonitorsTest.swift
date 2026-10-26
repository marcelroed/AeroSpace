@testable import AppBundle
import Common
import Testing

@Suite
struct ListMonitorsTest: AeroSpaceTestSuite {
    @Test
    func testParseListMonitorsCommand() {
        testParseSingleCommandSucc("list-monitors", ListMonitorsCmdArgs(rawArgs: []))
        testParseSingleCommandSucc("list-monitors --focused", ListMonitorsCmdArgs(rawArgs: []).copy(\.focused, true))
        testParseSingleCommandSucc("list-monitors --count", ListMonitorsCmdArgs(rawArgs: []).copy(\.outputOnlyCount, true))
        assertEquals(parseCommand("list-monitors --format %{monitor-id} --count").errorOrNil, "ERROR: Conflicting options: --count, --format")
    }

    @Test
    func testParseMissingFormatListsPossibleValues() {
        assertEquals(
            parseCommand("list-monitors --format").errorOrNil,
            "ERROR: <output-format> is mandatory. Possible values:\n" +
                "         monitor-id\n         monitor-appkit-nsscreen-screens-id\n         monitor-name\n         monitor-is-main\n" +
                "         right-padding\n         newline\n         tab",
        )
    }
}
