@testable import AppBundle
import Common
import Testing

/// The parse only: the fake platform doesn't move the mouse. GenericParseErrorTest has the parse errors
@Suite(.aeroSpaceGlobalState)
struct MoveMouseCommandTest {
    @Test(arguments: [
        ("move-mouse window-lazy-center", .windowLazyCenter),
        ("move-mouse window-force-center", .windowForceCenter),
        ("move-mouse monitor-lazy-center", .monitorLazyCenter),
        ("move-mouse --fail-if-noop monitor-lazy-center", .monitorLazyCenter),
        ("move-mouse monitor-force-center", .monitorForceCenter),
    ] as [(String, MoveMouseCommand.MouseTarget)])
    func parse(raw: String, expected: MoveMouseCommand.MouseTarget) {
        expectEqual(parsedCmd(raw, as: MoveMouseCommand.self)?.mouseTarget, expected)
    }
}
