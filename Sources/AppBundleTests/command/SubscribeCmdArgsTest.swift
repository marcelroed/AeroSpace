@testable import AppBundle
import Common
import Testing

@Suite
struct SubscribeCmdArgsTest: AeroSpaceTestSuite {
    @Test
    func testParseValidEvents() {
        assertEquals(parseSubscribeCmdArgs(["focus-changed", "mode-changed"].slice).cmdOrNil?.events, Set([.focusChanged, .modeChanged]))
    }

    @Test
    func testParseAllFlag() {
        assertEquals(parseSubscribeCmdArgs(["--all"].slice).cmdOrNil?.events, Set(ServerEventType.allCases))
    }

    @Test
    func testParseUnknownEvent() {
        let expectedMsg = """
            ERROR: Can't parse 'unknown-event'.
                   Possible values: (focus-changed|focused-monitor-changed|focused-workspace-changed|mode-changed|window-detected|binding-triggered)
            """
        assertEquals(parseSubscribeCmdArgs(["unknown-event"].slice).failureOrNil, CmdParsingFailure(expectedMsg, 2))
    }

    @Test
    func testParseUnknownEventAfterDuplicateEventIsReportedOnce() {
        // The parser used to advance by the number of distinct events, so it read 'bogus' again
        // and added a bogus "Unknown argument" error (RB-14)
        let result = parseSubscribeCmdArgs(["focus-changed", "focus-changed", "bogus"].slice)
        switch result {
            case .cmd, .help:
                fail("Expected failure")
            case .failure(let err):
                let expectedMsg = """
                    ERROR: Can't parse 'bogus'.
                           Possible values: (focus-changed|focused-monitor-changed|focused-workspace-changed|mode-changed|window-detected|binding-triggered)
                    """
                assertEquals(err, .init(expectedMsg, 2))
        }
    }

    @Test
    func testParseDuplicateEvent() {
        assertEquals(parseSubscribeCmdArgs(["focus-changed", "focus-changed"].slice).failureOrNil, CmdParsingFailure("ERROR: Duplicate event 'focus-changed'", 2))
    }

    @Test
    func testParseNoEvents() {
        assertEquals(parseSubscribeCmdArgs([String]().slice).failureOrNil, CmdParsingFailure("ERROR: Either --all or at least one <event> must be specified", 2))
    }

    @Test
    func testParseAllWithEventsConflict() {
        assertEquals(parseSubscribeCmdArgs(["--all", "focus-changed"].slice).failureOrNil, CmdParsingFailure("ERROR: --all conflicts with specifying individual events", 2))
    }
}
