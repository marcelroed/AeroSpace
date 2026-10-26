@testable import AppBundle
import Common
import XCTest

@MainActor
final class EnableCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }
    override func tearDown() async throws {
        TrayMenuModel.shared.isEnabled = true
        activeMode = mainModeId
    }

    func testParse() {
        testParseSingleCommandSucc("enable on", EnableCmdArgs(rawArgs: [], targetState: .on))
        testParseSingleCommandSucc("enable off", EnableCmdArgs(rawArgs: [], targetState: .off))
        testParseSingleCommandSucc("enable toggle", EnableCmdArgs(rawArgs: [], targetState: .toggle))
        testParseSingleCommandSucc("enable --fail-if-noop on", EnableCmdArgs(rawArgs: [], targetState: .on).copy(\.failIfNoop, true))
        assertEquals(parseCommand("enable toggle --fail-if-noop").errorOrNil, "--fail-if-noop is incompatible with 'toggle' argument")
        assertEquals(parseCommand("enable foo").errorOrNil, "ERROR: Can't parse 'foo'.\n       Possible values: (on|off|toggle)")
        assertEquals(parseCommand("enable").errorOrNil, "ERROR: Argument '(on|off|toggle)' is mandatory")
    }

    func testNoop() async {
        var result = await parseCommand("enable on").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, ["Already enabled. Tip: use --fail-if-noop to exit with non-zero code"])
        assertTrue(TrayMenuModel.shared.isEnabled)

        result = await parseCommand("enable on --fail-if-noop").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, [])

        TrayMenuModel.shared.isEnabled = false
        result = await parseCommand("enable off").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, ["Already disabled. Tip: use --fail-if-noop to exit with non-zero code"])
        assertFalse(TrayMenuModel.shared.isEnabled)

        result = await parseCommand("enable off --fail-if-noop").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, [])
    }

    func testToggle() async {
        var result = await parseCommand("enable toggle").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, [])
        assertFalse(TrayMenuModel.shared.isEnabled)
        assertNil(activeMode)

        result = await parseCommand("enable toggle").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, [])
        assertTrue(TrayMenuModel.shared.isEnabled)
        assertEquals(activeMode, mainModeId)
    }
}
