@testable import AppBundle
import Common
import Testing

private let possibleEvents = "(focus-changed|focused-monitor-changed|focused-workspace-changed|mode-changed|window-detected|binding-triggered)"

private func parseSubscribe(_ args: [String]) -> Result<SubscribeArgs, CmdParseError> {
    Result { () throws(CmdParseError) in
        var cursor = ArgCursor(args)
        return try SubscribeArgs.parse(&cursor)
    }
}

@Suite
struct SubscribeCmdArgsTest {
    @Test
    func parseValidEvents() {
        #expect(parseSubscribe(["focus-changed", "mode-changed"]) == .success(SubscribeArgs(events: [.focusChanged, .modeChanged])))
        #expect(parseSubscribe(["--no-send-initial", "mode-changed"]) == .success(SubscribeArgs(events: [.modeChanged], sendInitial: false)))
    }

    @Test
    func parseAllFlag() {
        #expect(parseSubscribe(["--all"]) == .success(SubscribeArgs(events: Set(ServerEventType.allCases))))
    }

    @Test
    func parseUnknownEvent() {
        #expect(parseSubscribe(["unknown-event"]) == .failure("Can't parse 'unknown-event'.\nPossible values: \(possibleEvents)"))
    }

    @Test
    func parseUnknownEventAfterDuplicateEvent() {
        // The parser used to read 'bogus' twice, and add a bogus "Unknown argument" error (RB-14)
        #expect(parseSubscribe(["focus-changed", "focus-changed", "bogus"]) == .failure("Can't parse 'bogus'.\nPossible values: \(possibleEvents)"))
    }

    @Test
    func parseDuplicateEvent() {
        #expect(parseSubscribe(["focus-changed", "focus-changed"]) == .failure("Duplicate event 'focus-changed'"))
    }

    @Test
    func parseNoEvents() {
        #expect(parseSubscribe([]) == .failure("Either --all or at least one <event> must be specified"))
    }

    @Test
    func parseAllWithEventsConflict() {
        #expect(parseSubscribe(["--all", "focus-changed"]) == .failure("--all conflicts with specifying individual events"))
    }

    @Test
    func parseUnknownOption() {
        #expect(parseSubscribe(["--bogus", "focus-changed"]) == .failure("Unknown flag '--bogus'"))
    }
}
