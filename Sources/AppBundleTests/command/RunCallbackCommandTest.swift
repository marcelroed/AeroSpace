@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct RunCallbackCommandTest {
    @Test
    func parse() {
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

    @Test(arguments: [
        ("run-callback", "ERROR: Argument '<callback>' is mandatory"),
        ("run-callback bogus", "ERROR: Can't parse 'bogus'.\n       Possible values: (on-window-detected|on-focus-changed|on-focused-monitor-changed)"),
        ("run-callback --for-every-window --window-id 1 on-window-detected", "ERROR: Conflicting options: --for-every-window, --window-id"),
        ("run-callback --for-every-window on-focus-changed", "ERROR: --for-every-window is only allowed with 'on-window-detected'"),
        ("run-callback --window-id 1 on-focused-monitor-changed", "ERROR: --window-id is only allowed with 'on-window-detected'"),
    ])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        #expect(output == .fail(error))
    }

    @Test(arguments: ["run-callback on-window-detected", "run-callback --for-every-window on-window-detected"])
    func onWindowDetectedWithoutCallbacksSucceeds(command: String) async {
        // RB-05: when no callback ran, the exit code was Int32ExitCode.succ, which used to be 2
        setUpTree("h_tiles(*1)")
        #expect(config.onWindowDetected.isEmpty)
        #expect(MacWindow.allWindows.isEmpty)
        let output = await runCmd(command)
        #expect(output == .ok)
    }

    @Test
    func forEveryWindowFollowsWindowDetection() async {
        // RB-32: like the real window detection, skip popups and unbound windows. Process the windows in window-id
        // order, and report the first failure instead of the exit code of the last window
        setUpTree("h_tiles(3 4) floating(1) macos_popup(2)")
        let unbound = testWindow(4)
        unbound.unbindFromParent()
        config.onWindowDetected = [
            WindowDetectedCallback(run: parseCommand("echo -- '%{window-id}'; test %{window-id} = 3").cmdOrDie),
        ]

        let io = CmdIo(stdin: .emptyStdin)
        let exitCode = await onWindowDetected(.defaultEnv, io, forEvery: [testWindow(3), unbound, testWindow(1), testWindow(2)])
        #expect(io.stdout == ["1", "3"])
        #expect(io.stderr == [])
        #expect(exitCode.rawValue == 1) // `test 1 = 3` of the floating window
    }
}
