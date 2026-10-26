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

    @Test
    func testForEveryWindowFollowsWindowDetection() async {
        // RB-32: like the real window detection, skip popups and unbound windows. Process the windows in window-id
        // order, and report the first failure instead of the exit code of the last window
        let workspace = Workspace.get(byName: name)
        assertTrue(workspace.focusWorkspace())
        let floating = TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer)
        let popup = TestWindow.new(id: 2, parent: macosPopupWindowsContainer)
        let tiling = TestWindow.new(id: 3, parent: workspace.rootTilingContainer)
        let unbound = TestWindow.new(id: 4, parent: workspace.rootTilingContainer)
        unbound.unbindFromParent()
        config.onWindowDetected = [
            WindowDetectedCallback(run: parseCommand("echo -- '%{window-id}'; test %{window-id} = 3").cmdOrDie),
        ]

        let io = CmdIoImpl(stdin: .emptyStdin)
        let exitCode = await onWindowDetected(.defaultEnv, io, forEvery: [tiling, unbound, floating, popup])
        assertEquals(io.stdout, ["1", "3"])
        assertEquals(io.stderr, [])
        assertEquals(exitCode.rawValue, 1) // `test 1 = 3` of the floating window
    }
}
