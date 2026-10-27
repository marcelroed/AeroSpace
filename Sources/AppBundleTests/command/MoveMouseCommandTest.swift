@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct MoveMouseCommandTest {
    @Test
    func testParse() {
        expectEqual(parseMouseTarget("move-mouse window-lazy-center"), .windowLazyCenter)
        expectEqual(parseMouseTarget("move-mouse window-force-center"), .windowForceCenter)
        expectEqual(parseMouseTarget("move-mouse monitor-lazy-center"), .monitorLazyCenter)
        expectEqual(parseMouseTarget("move-mouse --fail-if-noop monitor-lazy-center"), .monitorLazyCenter)
        expectEqual(parseMouseTarget("move-mouse monitor-force-center"), .monitorForceCenter)

        expectEqual(parseCommand("move-mouse").errorOrNil, "Argument '<mouse-position>' is mandatory")
        expectEqual(
            parseCommand("move-mouse foo").errorOrNil,
            "Can't parse 'foo'.\nPossible values: (monitor-lazy-center|monitor-force-center|window-lazy-center|window-force-center)",
        )
        expectEqual(
            parseCommand("move-mouse --fail-if-noop window-force-center").errorOrNil,
            "--fail-if-noop is only compatible with window-lazy-center or monitor-lazy-center",
        )
    }
}

private func parseMouseTarget(_ raw: String) -> MoveMouseCommand.MouseTarget? {
    parsedCmd(raw, as: MoveMouseCommand.self)?.mouseTarget
}
