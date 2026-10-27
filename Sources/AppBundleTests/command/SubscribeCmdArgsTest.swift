@testable import AppBundle
import Common
import Testing

@Suite
struct SubscribeCmdArgsTest: AeroSpaceTestSuite {
    @Test
    func testParseValidEvents() {
        let result = parseSubscribeCmdArgs(["focus-changed", "mode-changed"].slice)
        switch result {
            case .cmd(let args):
                assertEquals(args.events, Set([.focusChanged, .modeChanged]))
            case .help, .failure:
                fail("Expected success")
        }
    }

    @Test
    func testParseAllFlag() {
        let result = parseSubscribeCmdArgs(["--all"].slice)
        switch result {
            case .cmd(let args):
                assertEquals(args.events, Set(ServerEventType.allCases))
            case .help, .failure:
                fail("Expected success")
        }
    }

    @Test
    func testParseUnknownEvent() {
        let result = parseSubscribeCmdArgs(["unknown-event"].slice)
        switch result {
            case .cmd, .help:
                fail("Expected failure")
            case .failure(let err):
                let expectedMsg = """
                    ERROR: Can't parse 'unknown-event'.
                           Possible values: (focus-changed|focused-monitor-changed|focused-workspace-changed|mode-changed|window-detected|binding-triggered)
                    """
                assertEquals(err, .init(expectedMsg, 2))
        }
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
        let result = parseSubscribeCmdArgs(["focus-changed", "focus-changed"].slice)
        switch result {
            case .cmd, .help:
                fail("Expected failure")
            case .failure(let err):
                assertEquals(err, .init("ERROR: Duplicate event 'focus-changed'", 2))
        }
    }

    @Test
    func testParseNoEvents() {
        let result = parseSubscribeCmdArgs([String]().slice)
        switch result {
            case .cmd, .help:
                fail("Expected failure")
            case .failure(let err):
                assertEquals(err, .init("ERROR: Either --all or at least one <event> must be specified", 2))
        }
    }

    @Test
    func testParseAllWithEventsConflict() {
        let result = parseSubscribeCmdArgs(["--all", "focus-changed"].slice)
        switch result {
            case .cmd, .help:
                fail("Expected failure")
            case .failure(let err):
                assertEquals(err, .init("ERROR: --all conflicts with specifying individual events", 2))
        }
    }
}
