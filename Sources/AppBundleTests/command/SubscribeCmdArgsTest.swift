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
        expectEqual(parseSubscribe(["focus-changed", "mode-changed"]), .success(SubscribeArgs(events: [.focusChanged, .modeChanged])))
        expectEqual(parseSubscribe(["--no-send-initial", "mode-changed"]), .success(SubscribeArgs(events: [.modeChanged], sendInitial: false)))
    }

    @Test
    func parseAllFlag() {
        expectEqual(parseSubscribe(["--all"]), .success(SubscribeArgs(events: Set(ServerEventType.allCases))))
    }

    @Test
    func parseUnknownEvent() {
        expectEqual(parseSubscribe(["unknown-event"]), .failure("Can't parse 'unknown-event'.\nPossible values: \(possibleEvents)"))
    }

    @Test
    func parseUnknownEventAfterDuplicateEvent() {
        // The parser used to read 'bogus' twice, and add a bogus "Unknown argument" error (RB-14)
        expectEqual(parseSubscribe(["focus-changed", "focus-changed", "bogus"]), .failure("Can't parse 'bogus'.\nPossible values: \(possibleEvents)"))
    }

    @Test
    func parseDuplicateEvent() {
        expectEqual(parseSubscribe(["focus-changed", "focus-changed"]), .failure("Duplicate event 'focus-changed'"))
    }

    @Test
    func parseNoEvents() {
        expectEqual(parseSubscribe([]), .failure("Either --all or at least one <event> must be specified"))
    }

    @Test
    func parseAllWithEventsConflict() {
        expectEqual(parseSubscribe(["--all", "focus-changed"]), .failure("--all conflicts with specifying individual events"))
    }

    @Test
    func parseUnknownOption() {
        expectEqual(parseSubscribe(["--bogus", "focus-changed"]), .failure("Unknown flag '--bogus'"))
    }
}
