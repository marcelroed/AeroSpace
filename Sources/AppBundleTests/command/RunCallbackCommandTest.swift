@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct RunCallbackCommandTest {
    @Test(arguments: [
        ("run-callback", "Argument '<callback>' is mandatory"),
        ("run-callback bogus", "Can't parse 'bogus'.\nPossible values: (on-window-detected|on-focus-changed|on-focused-monitor-changed)"),
        ("run-callback --for-every-window --window-id 1 on-window-detected", "Conflicting options: --for-every-window, --window-id"),
        ("run-callback --for-every-window on-focus-changed", "--for-every-window is only allowed with 'on-window-detected'"),
        ("run-callback --window-id 1 on-focused-monitor-changed", "--window-id is only allowed with 'on-window-detected'"),
    ] as [(String, String)])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        expectEqual(output, .fail(error))
    }

    @Test(arguments: ["run-callback on-window-detected", "run-callback --for-every-window on-window-detected", "run-callback --window-id 1 on-window-detected"])
    func onWindowDetectedWithoutCallbacksSucceeds(command: String) async {
        // RB-05: when no callback ran, the exit code used to be 2
        setUpTree("h_tiles(*1)")
        #expect(config.onWindowDetected.isEmpty)
        let output = await runCmd(command)
        expectEqual(output, .ok)
    }

    @Test
    func forEveryWindowFollowsWindowDetection() async {
        // RB-32: like the real window detection, skip popups and unbound windows. Process the windows in window-id
        // order, and report the first failure instead of the exit code of the last window
        setUpTree("h_tiles(3 4) floating(1) macos_popup(2)")
        let unbound = testWindow(4)
        unbound.unbindFromParent()
        world.config.onWindowDetected = [
            WindowDetectedCallback(run: parseCommand("echo -- '%{window-id}'; test %{window-id} = 3").cmdOrDie),
        ]

        let io = CmdIo(stdin: .emptyStdin)
        let exitCode = await onWindowDetected(.defaultEnv, io, forEvery: [testWindow(3), unbound, testWindow(1), testWindow(2)])
        expectEqual(io.stdout, ["1", "3"])
        expectEqual(io.stderr, [])
        expectEqual(exitCode, 1) // `test 1 = 3` of the floating window
    }

    @Test(arguments: RunCallbackCommand.CallbackKind.allCases)
    func callbackThatRunsItselfFails(callback: RunCallbackCommand.CallbackKind) async { // RB-120
        setUpTree("h_tiles(*1)")
        let command = "run-callback \(callback.rawValue)"
        let shell = parseCommand(command).cmdOrDie
        switch callback {
            case .onWindowDetected: world.config.onWindowDetected = [WindowDetectedCallback(run: shell)]
            case .onFocusChanged: world.config.onFocusChanged = shell
            case .onFocusedMonitorChanged: world.config.onFocusedMonitorChanged = shell
        }

        let output = await runCmd(command)
        expectEqual(output, .fail(nestsTooDeeply(command)))
    }

    @Test
    func focusChangeCallbackThatRunsItselfStops() async {
        setUpTree("h_tiles(*1)")
        await checkOnFocusChangedCallbacks_nonCancellable() // Remember the focus
        // The `mode` commands nested in the run-callback fail without running once it nests too deeply. The outermost
        // one runs. The callback's error goes nowhere, like every error of a callback
        world.config.onFocusChanged = parseCommand("run-callback on-focus-changed; mode callback-ran").cmdOrDie

        let output = await runCmd("workspace b")
        expectEqual(output, .ok)
        expectEqual(world.activeMode, "callback-ran")
    }
}
