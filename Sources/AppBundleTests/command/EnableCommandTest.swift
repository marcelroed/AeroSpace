@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct EnableCommandTest: AeroSpaceTestSuite {
    @Test
    func testParse() {
        testParseSingleCommandSucc("enable on", EnableCmdArgs(rawArgs: [], targetState: .on))
        testParseSingleCommandSucc("enable off", EnableCmdArgs(rawArgs: [], targetState: .off))
        testParseSingleCommandSucc("enable toggle", EnableCmdArgs(rawArgs: [], targetState: .toggle))
        testParseSingleCommandSucc("enable --fail-if-noop on", EnableCmdArgs(rawArgs: [], targetState: .on).copy(\.failIfNoop, true))
        assertEquals(parseCommand("enable toggle --fail-if-noop").errorOrNil, "--fail-if-noop is incompatible with 'toggle' argument")
        assertEquals(parseCommand("enable foo").errorOrNil, "ERROR: Can't parse 'foo'.\n       Possible values: (on|off|toggle)")
        assertEquals(parseCommand("enable").errorOrNil, "ERROR: Argument '(on|off|toggle)' is mandatory")
    }

    @Test
    func testNoop() async {
        await assertRun("enable on", exitCode: 0, stderr: ["Already enabled. Tip: use --fail-if-noop to exit with non-zero code"])
        assertTrue(TrayMenuModel.shared.isEnabled)

        await assertRun("enable on --fail-if-noop", exitCode: 2, stderr: [])

        TrayMenuModel.shared.isEnabled = false
        await assertRun("enable off", exitCode: 0, stderr: ["Already disabled. Tip: use --fail-if-noop to exit with non-zero code"])
        assertFalse(TrayMenuModel.shared.isEnabled)

        await assertRun("enable off --fail-if-noop", exitCode: 2, stderr: [])
    }

    @Test
    func testToggle() async {
        await assertRun("enable toggle", exitCode: 0, stderr: [])
        assertFalse(TrayMenuModel.shared.isEnabled)
        assertNil(activeMode)

        await assertRun("enable toggle", exitCode: 0, stderr: [])
        assertTrue(TrayMenuModel.shared.isEnabled)
        assertEquals(activeMode, mainModeId)
    }
}
