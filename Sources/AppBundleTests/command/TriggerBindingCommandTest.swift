@testable import AppBundle
import Common
import HotKey
import Testing

@Suite(.aeroSpaceGlobalState)
struct TriggerBindingCommandTest {
    @Test(arguments: [
        ("trigger-binding foo", "--mode flag is mandatory"),
        ("trigger-binding", "--mode flag is mandatory"), // The options are checked before the arguments
        ("trigger-binding --mode main --", "Argument '<binding>' is mandatory"),
    ] as [(String, String)])
    func parseError(command: String, error: String) async {
        let output = await runCmd(command)
        expectEqual(output, .fail(error))
    }

    @Test
    func unknownMode_listsAvailableModesSorted() async {
        // Ten modes, so that the dictionary order can't match the sorted order by chance (RB-13)
        let modeNames = ["main", "service", "resize", "move", "a", "z", "b", "y", "c", "x"]
        world.config.modes = Dictionary(uniqueKeysWithValues: modeNames.map { ($0, Mode(bindings: [:])) })

        let output = await runCmd("trigger-binding alt-h --mode unknown")
        expectEqual(output, .fail("Mode 'unknown' doesn't exist. Available modes: a,b,c,main,move,resize,service,x,y,z"))
    }

    /// `bindings` are the commands of alt-a, alt-b, ... in the main mode
    @Test(arguments: [
        // RB-120: it used to recurse until AeroSpace ran out of memory. The `true` 33 levels deep fails, and the error
        // names the command that runs it
        (["true; trigger-binding --mode main alt-a"], "trigger-binding --mode main alt-a", .fail(nestsTooDeeply("trigger-binding --mode main alt-a"))),
        // The CLI command is level 1, so the command of alt-a, which triggers alt-b, is level 32
        (["trigger-binding --mode main alt-b", "trigger-binding --mode main alt-a"], "trigger-binding --mode main alt-a", .fail(nestsTooDeeply("trigger-binding --mode main alt-b"))),
        // Each level runs two nested levels. The commands that are left fail without running when the limit is reached,
        // otherwise this would run 2^32 commands
        (
            ["trigger-binding --mode main alt-a; trigger-binding --mode main alt-a; echo unreachable"],
            "trigger-binding --mode main alt-a; echo next",
            CmdOutput(stdout: ["next"], stderr: [nestsTooDeeply("trigger-binding --mode main alt-a")]),
        ),
        // No loop
        (["trigger-binding --mode main alt-b", "echo b; trigger-binding --mode main alt-c", "echo c"], "trigger-binding --mode main -- alt-a", CmdOutput(stdout: ["b", "c"])),
    ] as [([String], String, CmdOutput)])
    func bindingLoops(bindings: [String], command: String, expected: CmdOutput) async {
        for (key, commands) in zip([Key.a, .b, .c], bindings) {
            bind(key, commands)
        }

        let output = await runCmd(command)
        expectEqual(output, expected)
    }

    /// A chain of `bindingCount` bindings in as many modes. The last one echoes
    @Test(arguments: [
        (31, CmdOutput(stdout: ["reached"])), // The echo is level 32: the CLI command is level 1
        (32, .fail(nestsTooDeeply("trigger-binding --mode m32 alt-a"))),
    ] as [(Int, CmdOutput)])
    func nestingIsLimitedTo32Levels(bindingCount: Int, expected: CmdOutput) async {
        for index in 1 ... bindingCount {
            bind(.a, index == bindingCount ? "echo reached" : "trigger-binding --mode m\(index + 1) alt-a", mode: "m\(index)")
        }

        let output = await runCmd("trigger-binding --mode m1 alt-a")
        expectEqual(output, expected)
    }
}

/// Binds `alt-<key>` to `commands`
private func bind(_ key: Key, _ commands: String, mode: String = mainModeId) {
    let binding = HotkeyBinding(.option, key, parseCommand(commands).cmdOrDie)
    world.config.modes[mode, default: .zero].bindings[binding.descriptionWithKeyCode] = binding
}

/// The error of a command that `command` runs more than 32 levels deep
nonisolated func nestsTooDeeply(_ command: String) -> String {
    "Commands nest too deeply (more than 32 levels). A binding or callback probably runs itself: \(command)"
}
