@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct MoveWorkspaceToMonitorCommandTest: AeroSpaceTestSuite {
    @Test
    func testParse() {
        assertEquals(parseMoveWorkspaceToMonitorTarget("move-workspace-to-monitor next"), .relative(.next))
        assertEquals(parseMoveWorkspaceToMonitorTarget("move-workspace-to-monitor main"), .patterns([.main]))
    }

    @Test
    func testParseDashDash() {
        assertEquals(parseMoveWorkspaceToMonitorTarget("move-workspace-to-monitor -- next"), .patterns([.pattern("next")!]))
        assertEquals(parseCommand("move-workspace-to-monitor --").errorOrNil, "ERROR: Argument \'(left|down|up|right|next|prev|<monitor-pattern>)\' is mandatory")
    }

    @Test
    func testParseDeprecatedAliasIsValidatedLikeTheCommand() {
        // The deprecated move-workspace-to-display alias used to skip the post-parse validation (RB-12)
        for command in ["move-workspace-to-monitor", "move-workspace-to-display"] {
            assertEquals(parseCommand("\(command) --wrap-around 2").errorOrNil, "--wrap-around is incompatible with <monitor-pattern> argument")
            assertEquals(parseMoveWorkspaceToMonitorTarget("\(command) --wrap-around next"), .relative(.next))
        }
    }
}

private func parseMoveWorkspaceToMonitorTarget(_ raw: String) -> MonitorTarget? {
    parsedArgs(raw, as: MoveWorkspaceToMonitorCmdArgs.self)?.target.val
}
