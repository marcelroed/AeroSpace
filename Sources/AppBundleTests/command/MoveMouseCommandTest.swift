@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct MoveMouseCommandTest: AeroSpaceTestSuite {
    @Test
    func testParse() {
        assertEquals(parseMouseTarget("move-mouse window-lazy-center"), .windowLazyCenter)
        assertEquals(parseMouseTarget("move-mouse window-force-center"), .windowForceCenter)
        assertEquals(parseMouseTarget("move-mouse monitor-lazy-center"), .monitorLazyCenter)
        assertEquals(parseMouseTarget("move-mouse --fail-if-noop monitor-lazy-center"), .monitorLazyCenter)
        assertEquals(parseMouseTarget("move-mouse monitor-force-center"), .monitorForceCenter)

        assertEquals(parseCommand("move-mouse").errorOrNil, "ERROR: Argument '<mouse-position>' is mandatory")
        assertEquals(
            parseCommand("move-mouse foo").errorOrNil,
            "ERROR: Can't parse 'foo'.\n       Possible values: (monitor-lazy-center|monitor-force-center|window-lazy-center|window-force-center)",
        )
        assertEquals(
            parseCommand("move-mouse --fail-if-noop window-force-center").errorOrNil,
            "--fail-if-noop is only compatible with window-lazy-center or monitor-lazy-center",
        )
    }
}

private func parseMouseTarget(_ raw: String) -> MouseTarget? {
    parsedArgs(raw, as: MoveMouseCmdArgs.self)?.mouseTarget.val
}
