@testable import AppBundle
import Common
import Testing

@Suite
struct ListMonitorsTest {
    @Test
    func testParseListMonitorsCommand() {
        testParseSingleCommandSucc("list-monitors", ListMonitorsCommand())
        testParseSingleCommandSucc("list-monitors --focused", ListMonitorsCommand(focused: true))
        testParseSingleCommandSucc("list-monitors --count", ListMonitorsCommand(output: .count))
        #expect(parseCommand("list-monitors --format %{monitor-id} --count").errorOrNil == "Conflicting options: --count, --format")
    }

    @Test
    func testParseMissingFormatListsPossibleValues() {
        #expect(
            parseCommand("list-monitors --format").errorOrNil == "<output-format> is mandatory. Possible values:\n" +
                "  monitor-id\n  monitor-appkit-nsscreen-screens-id\n  monitor-name\n  monitor-is-main\n" +
                "  right-padding\n  newline\n  tab",
        )
    }
}
