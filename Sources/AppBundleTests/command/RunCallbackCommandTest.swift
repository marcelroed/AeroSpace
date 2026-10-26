@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct RunCallbackCommandTest: AeroSpaceTestSuite {
    @Test
    func testParse() {
        testParseSingleCommandSucc(
            "run-callback on-window-detected",
            RunCallbackCmdArgs(rawArgs: []).copy(\.callback, .initialized(.onWindowDetected)),
        )
        testParseSingleCommandSucc(
            "run-callback --for-every-window on-window-detected",
            RunCallbackCmdArgs(rawArgs: [])
                .copy(\.callback, .initialized(.onWindowDetected))
                .copy(\.forEveryWindow, true),
        )
        testParseSingleCommandSucc(
            "run-callback --window-id 42 on-window-detected",
            RunCallbackCmdArgs(rawArgs: [])
                .copy(\.callback, .initialized(.onWindowDetected))
                .copy(\.windowId, 42),
        )
        testParseSingleCommandSucc(
            "run-callback on-focus-changed",
            RunCallbackCmdArgs(rawArgs: []).copy(\.callback, .initialized(.onFocusChanged)),
        )
        testParseSingleCommandSucc(
            "run-callback on-focused-monitor-changed",
            RunCallbackCmdArgs(rawArgs: []).copy(\.callback, .initialized(.onFocusedMonitorChanged)),
        )
    }

    @Test
    func testParseFailure() {
        testParseCommandFail("run-callback", msg: "ERROR: Argument '<callback>' is mandatory", exitCode: 2)
        testParseCommandFail(
            "run-callback bogus",
            msg: "ERROR: Can't parse 'bogus'.\n       Possible values: (on-window-detected|on-focus-changed|on-focused-monitor-changed)",
            exitCode: 2,
        )
        testParseCommandFail(
            "run-callback --for-every-window --window-id 1 on-window-detected",
            msg: "ERROR: Conflicting options: --for-every-window, --window-id",
            exitCode: 2,
        )
        testParseCommandFail(
            "run-callback --for-every-window on-focus-changed",
            msg: "--for-every-window is only allowed with 'on-window-detected'",
            exitCode: 2,
        )
        testParseCommandFail(
            "run-callback --window-id 1 on-focused-monitor-changed",
            msg: "--window-id is only allowed with 'on-window-detected'",
            exitCode: 2,
        )
    }

    @Test
    func testOnWindowDetectedWithoutCallbacksSucceeds() async {
        // RB-05: when no callback ran, the exit code was Int32ExitCode.succ, which used to be 2
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }
        assertEquals(config.onWindowDetected.count, 0)

        assertEquals(
            await parseCommand("run-callback on-window-detected").cmdOrDie.run(.defaultEnv, .emptyStdin),
            CmdResult(stdout: [], stderr: [], exitCode: Int32ExitCode(rawValue: 0)),
        )
        assertEquals(MacWindow.allWindows.count, 0)
        assertEquals(
            await parseCommand("run-callback --for-every-window on-window-detected").cmdOrDie.run(.defaultEnv, .emptyStdin),
            CmdResult(stdout: [], stderr: [], exitCode: Int32ExitCode(rawValue: 0)),
        )
    }
}
