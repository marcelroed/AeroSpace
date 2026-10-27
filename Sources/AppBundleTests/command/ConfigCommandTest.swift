@testable import AppBundle
import Common
import Foundation
import HotKey
import Testing

@Suite(.aeroSpaceGlobalState)
struct ConfigCommandTest {
    @Test
    func testParse() {
        expectEqual(parseCommand("config --major-keys").errorOrNil, nil)
        expectEqual(parseCommand("config --all-keys").errorOrNil, nil)
        expectEqual(parseCommand("config --config-path").errorOrNil, nil)
        expectEqual(parseCommand("config --get foo").errorOrNil, nil)
        expectEqual(parseCommand("config --get foo --keys").errorOrNil, nil)
        expectEqual(parseCommand("config --get foo --json").errorOrNil, nil)
        expectEqual(parseCommand("config --get foo --keys --json").errorOrNil, nil)

        expectEqual(parseCommand("config").errorOrNil, "Mandatory flag is not specified (--get|--major-keys|--all-keys|--config-path)")
        // --keys/--json alone still trigger the mandatory-flag check first because they don't
        // contribute to the mandatory-flag set.
        expectEqual(parseCommand("config --keys").errorOrNil, "Mandatory flag is not specified (--get|--major-keys|--all-keys|--config-path)")
        expectEqual(parseCommand("config --json").errorOrNil, "Mandatory flag is not specified (--get|--major-keys|--all-keys|--config-path)")
        expectEqual(parseCommand("config --major-keys --keys").errorOrNil, "--keys flag requires --get flag")
        expectEqual(parseCommand("config --major-keys --json").errorOrNil, "--json flag requires --get flag")

        // Two mandatory flags are mutually exclusive
        expectEqual(parseCommand("config --major-keys --all-keys").errorOrNil, "Conflicting flags are specified: --major-keys, --all-keys")
    }

    @Test
    func testParse_conflictingFlagsAreListedInFixedOrder() {
        // Every combination of two or more mandatory flags, passed in reverse order. The flags used to be collected
        // in a Set, whose order is random. The eleven combinations make an unordered collection fail reliably (RB-13)
        let flags: [(name: String, args: String)] =
            [("--get", "--get foo"), ("--major-keys", "--major-keys"), ("--all-keys", "--all-keys"), ("--config-path", "--config-path")]
        for mask in 0 ..< (1 << flags.count) where mask.nonzeroBitCount >= 2 {
            let combination = flags.indices.filter { mask & (1 << $0) != 0 }.map { flags[$0] }
            expectEqual(parseCommand("config " + combination.reversed().map(\.args).joined(separator: " ")).errorOrNil, "Conflicting flags are specified: " + combination.map(\.name).joined(separator: ", "))
        }
    }

    @Test
    func testConfigPath() async {
        let output = await runCmd("config --config-path")
        expectEqual(output, CmdOutput(stdout: [world.configUrl.absoluteURL.path]))
    }

    @Test
    func testMajorKeys() async {
        world.config.modes = [
            "main": Mode(bindings: [:]),
            "service": Mode(bindings: [:]),
        ]
        let output = await runCmd("config --major-keys")
        // The whole listing comes back as one stdout entry separated by newlines.
        expectEqual(output, CmdOutput(stdout: [".\nmode\nmode.main.binding\nmode.service.binding"]))
    }

    @Test
    func testMajorKeys_sortedOutput() async {
        // Ten modes, so that the dictionary order can't match the sorted order by chance (RB-13)
        world.config.modes = manyModes()
        let expected = [".", "mode"] + manyModeNames.sorted().map { "mode.\($0).binding" }
        let output = await runCmd("config --major-keys")
        expectEqual(output, CmdOutput(stdout: [expected.joined(separator: "\n")]))
    }

    @Test
    func testAllKeys() async {
        bindAltHToFocusLeft()

        // Single mode + single binding => dict iteration order doesn't affect the output.
        let output = await runCmd("config --all-keys")
        expectEqual(output, CmdOutput(stdout: [".\nmode\nmode.main\nmode.main.binding\nmode.main.binding.alt-h"]))
    }

    @Test
    func testAllKeys_sortedOutput() async {
        let command = parseCommand("focus left").cmdOrDie
        let bindings = [HotkeyBinding(.option, .k, command), HotkeyBinding(.option, .h, command), HotkeyBinding(.option, .j, command)]
        world.config.modes = manyModes(bindings: Dictionary(uniqueKeysWithValues: bindings.map { ($0.descriptionWithKeyCode, $0) }))

        let modeKeys: [String] = manyModeNames.sorted().flatMap { (mode: String) -> [String] in
            ["mode.\(mode)", "mode.\(mode).binding", "mode.\(mode).binding.alt-h", "mode.\(mode).binding.alt-j", "mode.\(mode).binding.alt-k"]
        }
        let expected: [String] = [".", "mode"] + modeKeys
        let output = await runCmd("config --all-keys")
        expectEqual(output, CmdOutput(stdout: [expected.joined(separator: "\n")]))
    }

    @Test
    func testGetRoot_complexObject_fails() async {
        let output = await runCmd("config --get .")
        expectEqual(output, .fail("Complicated objects can be printed only with --json flag. Alternatively, you can try to inspect keys of the object with --keys flag"))
    }

    @Test
    func testGetRoot_keys() async {
        world.config.modes = ["main": Mode(bindings: [:])]
        let output = await runCmd("config --get . --keys")
        expectEqual(output, CmdOutput(stdout: ["mode"]))
    }

    @Test
    func testGetRoot_json() async {
        world.config.modes = ["main": Mode(bindings: [:])]
        let expectedMap: OrderedJson = .dict(["mode": .dict(["main": .dict(["binding": .dict([:])])])])
        let expectedJson = JSONEncoder.aeroSpaceDefault.encodeToString(expectedMap)

        let output = await runCmd("config --get . --json")
        expectEqual(output, CmdOutput(stdout: [expectedJson.orDie()]))
    }

    @Test
    func testGetRoot_keysJson() async {
        world.config.modes = ["main": Mode(bindings: [:])]
        // --keys converts the map into an array of string-scalar keys, which is then JSON-encoded.
        let expected = JSONEncoder.aeroSpaceDefault.encodeToString(
            OrderedJson.array([.string("mode")]),
        )

        let output = await runCmd("config --get . --keys --json")
        expectEqual(output, CmdOutput(stdout: [expected.orDie()]))
    }

    @Test
    func testGetMode_keys_sortedOutput() async {
        world.config.modes = [
            "main": Mode(bindings: [:]),
            "service": Mode(bindings: [:]),
        ]
        // Plain (non-json) array output is sorted before printing.
        let output = await runCmd("config --get mode --keys")
        expectEqual(output, CmdOutput(stdout: ["main\nservice"]))
    }

    @Test
    func testGetMode_keysJson_sortedOutput() async {
        world.config.modes = manyModes()
        let expected = JSONEncoder.aeroSpaceDefault.encodeToString(
            OrderedJson.array(manyModeNames.sorted().map { .string($0) }),
        )

        let output = await runCmd("config --get mode --keys --json")
        expectEqual(output, CmdOutput(stdout: [expected.orDie()]))
    }

    @Test
    func testGetScalar() async {
        let command = bindAltHToFocusLeft()

        let output = await runCmd("config --get mode.main.binding.alt-h")
        expectEqual(output, CmdOutput(stdout: [command.shellOfCommandsDescription]))
    }

    @Test
    func testGetScalar_keys_fails() async {
        let command = bindAltHToFocusLeft()

        let output = await runCmd("config --get mode.main.binding.alt-h --keys")
        expectEqual(output, .fail("--keys flag cannot be applied to scalar object '\(command.shellOfCommandsDescription)'"))
    }

    @Test
    func testGetScalar_dereference_fails() async {
        let command = bindAltHToFocusLeft()

        let output = await runCmd("config --get mode.main.binding.alt-h.foo")
        expectEqual(output, .fail("Can't dereference scalar value '\(command.shellOfCommandsDescription)'"))
    }

    @Test
    func testGetMissingKey_fails() async {
        let output = await runCmd("config --get nonExistent")
        expectEqual(output, .fail("No value at key token 'nonExistent'"))
    }

    @Test
    func testGetInvalidPath_emptyKey() async {
        let output = await runCmd("config --get ''")
        expectEqual(output, .fail("Invalid empty key"))
    }

    @Test
    func testGetInvalidPath_doubleDot() async {
        let output = await runCmd("config --get a..b")
        expectEqual(output, .fail("Invalid key 'a..b'"))
    }

    @Test
    func testGetInvalidPath_trailingDot() async {
        let output = await runCmd("config --get a.")
        expectEqual(output, .fail("Invalid key 'a.'"))
    }

    @Test
    func testGetMode_json_literal() async {
        let command = parseCommand("focus left").cmdOrDie
        let binding = HotkeyBinding(.option, .h, command)
        let binding2 = HotkeyBinding(.option, .j, parseCommand("focus down").cmdOrDie)
        world.config.modes = ["main": Mode(bindings: [binding.descriptionWithKeyCode: binding, binding2.descriptionWithKeyCode: binding2])]

        let expected = """
            {
              "main" : {
                "binding" : {
                  "alt-h" : "focus left",
                  "alt-j" : "focus down"
                }
              }
            }
            """
        let output = await runCmd("config --get mode --json")
        expectEqual(output, CmdOutput(stdout: [expected]))
    }

    @Test
    func testGetRoot_json_literal() async {
        world.config.modes = ["main": Mode(bindings: [:])]
        let expected = """
            {
              "mode" : {
                "main" : {
                  "binding" : {

                  }
                }
              }
            }
            """
        let output = await runCmd("config --get . --json")
        expectEqual(output, CmdOutput(stdout: [expected]))
    }

    @Test
    func testGetMode_keysJson_literal() async {
        world.config.modes = ["main": Mode(bindings: [:])]
        let output = await runCmd("config --get mode.main --keys --json")
        expectEqual(output, CmdOutput(stdout: ["[\n  \"binding\"\n]"]))
    }

    @Test
    func testGetScalar_json_literal() async {
        bindAltHToFocusLeft()
        let output = await runCmd("config --get mode.main.binding.alt-h --json")
        expectEqual(output, CmdOutput(stdout: ["\"focus left\""]))
    }

    @Test
    func testEncodeArray_literal() {
        let value: OrderedJson = .array([.string("a/b"), .int(1), .dict(["k": .array([])]), .array([.int(0)])])
        let expected = """
            [
              "a/b",
              1,
              {
                "k" : [

                ]
              },
              [
                0
              ]
            ]
            """
        expectEqual(JSONEncoder.aeroSpaceDefault.encodeToString(value), expected)
    }

    /// Binds alt-h to `focus left` in the main mode, and returns that command
    @discardableResult
    private func bindAltHToFocusLeft() -> Shell<any Command> {
        let command = parseCommand("focus left").cmdOrDie
        let binding = HotkeyBinding(.option, .h, command)
        world.config.modes = ["main": Mode(bindings: [binding.descriptionWithKeyCode: binding])]
        return command
    }
}

/// Enough modes that a dictionary order can't match the sorted order by chance
private let manyModeNames = ["main", "service", "resize", "move", "a", "z", "b", "y", "c", "x"]

private func manyModes(bindings: [String: HotkeyBinding] = [:]) -> [String: Mode] {
    Dictionary(uniqueKeysWithValues: manyModeNames.map { ($0, Mode(bindings: bindings)) })
}
