@testable import AppBundle
import Common
import Foundation
import HotKey
import Testing

@Suite(.aeroSpaceGlobalState)
struct ConfigCommandTest: AeroSpaceTestSuite {
    @Test
    func testParse() {
        #expect(parseCommand("config --major-keys").errorOrNil == nil)
        #expect(parseCommand("config --all-keys").errorOrNil == nil)
        #expect(parseCommand("config --config-path").errorOrNil == nil)
        #expect(parseCommand("config --get foo").errorOrNil == nil)
        #expect(parseCommand("config --get foo --keys").errorOrNil == nil)
        #expect(parseCommand("config --get foo --json").errorOrNil == nil)
        #expect(parseCommand("config --get foo --keys --json").errorOrNil == nil)

        #expect(parseCommand("config").errorOrNil == "ERROR: Mandatory flag is not specified (--get|--major-keys|--all-keys|--config-path)")
        // --keys/--json alone still trigger the mandatory-flag check first because they don't
        // contribute to the mandatory-flag set.
        #expect(parseCommand("config --keys").errorOrNil == "ERROR: Mandatory flag is not specified (--get|--major-keys|--all-keys|--config-path)")
        #expect(parseCommand("config --json").errorOrNil == "ERROR: Mandatory flag is not specified (--get|--major-keys|--all-keys|--config-path)")
        #expect(parseCommand("config --major-keys --keys").errorOrNil == "ERROR: --keys flag requires --get flag")
        #expect(parseCommand("config --major-keys --json").errorOrNil == "ERROR: --json flag requires --get flag")

        // Two mandatory flags are mutually exclusive
        #expect(parseCommand("config --major-keys --all-keys").errorOrNil == "ERROR: Conflicting flags are specified: --major-keys, --all-keys")
    }

    @Test
    func testParse_conflictingFlagsAreListedInFixedOrder() {
        // Every combination of two or more mandatory flags, passed in reverse order. The flags used to be collected
        // in a Set, whose order is random. The eleven combinations make an unordered collection fail reliably (RB-13)
        let flags: [(name: String, args: String)] =
            [("--get", "--get foo"), ("--major-keys", "--major-keys"), ("--all-keys", "--all-keys"), ("--config-path", "--config-path")]
        for mask in 0 ..< (1 << flags.count) where mask.nonzeroBitCount >= 2 {
            let combination = flags.indices.filter { mask & (1 << $0) != 0 }.map { flags[$0] }
            #expect(parseCommand("config " + combination.reversed().map(\.args).joined(separator: " ")).errorOrNil == "ERROR: Conflicting flags are specified: " + combination.map(\.name).joined(separator: ", "))
        }
    }

    @Test
    func testConfigPath() async {
        let output = await runCmd("config --config-path")
        #expect(output == CmdOutput(stdout: [configUrl.absoluteURL.path]))
    }

    @Test
    func testMajorKeys() async {
        config.modes = [
            "main": Mode(bindings: [:]),
            "service": Mode(bindings: [:]),
        ]
        let output = await runCmd("config --major-keys")
        // The whole listing comes back as one stdout entry separated by newlines.
        #expect(output == CmdOutput(stdout: [".\nmode\nmode.main.binding\nmode.service.binding"]))
    }

    @Test
    func testMajorKeys_sortedOutput() async {
        // Ten modes, so that the dictionary order can't match the sorted order by chance (RB-13)
        config.modes = manyModes()
        let expected = [".", "mode"] + manyModeNames.sorted().map { "mode.\($0).binding" }
        let output = await runCmd("config --major-keys")
        #expect(output == CmdOutput(stdout: [expected.joined(separator: "\n")]))
    }

    @Test
    func testAllKeys() async {
        bindAltHToFocusLeft()

        // Single mode + single binding => dict iteration order doesn't affect the output.
        let output = await runCmd("config --all-keys")
        #expect(output == CmdOutput(stdout: [".\nmode\nmode.main\nmode.main.binding\nmode.main.binding.alt-h"]))
    }

    @Test
    func testAllKeys_sortedOutput() async {
        let command = parseCommand("focus left").cmdOrDie
        let bindings = [HotkeyBinding(.option, .k, command), HotkeyBinding(.option, .h, command), HotkeyBinding(.option, .j, command)]
        config.modes = manyModes(bindings: Dictionary(uniqueKeysWithValues: bindings.map { ($0.descriptionWithKeyCode, $0) }))

        let expected = [".", "mode"] + manyModeNames.sorted().flatMap { mode in
            ["mode.\(mode)", "mode.\(mode).binding"] + ["alt-h", "alt-j", "alt-k"].map { "mode.\(mode).binding.\($0)" }
        }
        let output = await runCmd("config --all-keys")
        #expect(output == CmdOutput(stdout: [expected.joined(separator: "\n")]))
    }

    @Test
    func testGetRoot_complexObject_fails() async {
        let output = await runCmd("config --get .")
        #expect(output == .fail("Complicated objects can be printed only with --json flag. Alternatively, you can try to inspect keys of the object with --keys flag"))
    }

    @Test
    func testGetRoot_keys() async {
        config.modes = ["main": Mode(bindings: [:])]
        let output = await runCmd("config --get . --keys")
        #expect(output == CmdOutput(stdout: ["mode"]))
    }

    @Test
    func testGetRoot_json() async {
        config.modes = ["main": Mode(bindings: [:])]
        let expectedMap: OrderedJson = .dict(["mode": .dict(["main": .dict(["binding": .dict([:])])])])
        let expectedJson = JSONEncoder.aeroSpaceDefault.encodeToString(expectedMap)

        let output = await runCmd("config --get . --json")
        #expect(output == CmdOutput(stdout: [expectedJson.orDie()]))
    }

    @Test
    func testGetRoot_keysJson() async {
        config.modes = ["main": Mode(bindings: [:])]
        // --keys converts the map into an array of string-scalar keys, which is then JSON-encoded.
        let expected = JSONEncoder.aeroSpaceDefault.encodeToString(
            OrderedJson.array([.string("mode")]),
        )

        let output = await runCmd("config --get . --keys --json")
        #expect(output == CmdOutput(stdout: [expected.orDie()]))
    }

    @Test
    func testGetMode_keys_sortedOutput() async {
        config.modes = [
            "main": Mode(bindings: [:]),
            "service": Mode(bindings: [:]),
        ]
        // Plain (non-json) array output is sorted before printing.
        let output = await runCmd("config --get mode --keys")
        #expect(output == CmdOutput(stdout: ["main\nservice"]))
    }

    @Test
    func testGetMode_keysJson_sortedOutput() async {
        config.modes = manyModes()
        let expected = JSONEncoder.aeroSpaceDefault.encodeToString(
            OrderedJson.array(manyModeNames.sorted().map { .string($0) }),
        )

        let output = await runCmd("config --get mode --keys --json")
        #expect(output == CmdOutput(stdout: [expected.orDie()]))
    }

    @Test
    func testGetScalar() async {
        let command = bindAltHToFocusLeft()

        let output = await runCmd("config --get mode.main.binding.alt-h")
        #expect(output == CmdOutput(stdout: [command.shellOfCommandsDescription]))
    }

    @Test
    func testGetScalar_keys_fails() async {
        let command = bindAltHToFocusLeft()

        let output = await runCmd("config --get mode.main.binding.alt-h --keys")
        #expect(output == .fail("--keys flag cannot be applied to scalar object '\(command.shellOfCommandsDescription)'"))
    }

    @Test
    func testGetScalar_dereference_fails() async {
        let command = bindAltHToFocusLeft()

        let output = await runCmd("config --get mode.main.binding.alt-h.foo")
        #expect(output == .fail("Can't dereference scalar value '\(command.shellOfCommandsDescription)'"))
    }

    @Test
    func testGetMissingKey_fails() async {
        let output = await runCmd("config --get nonExistent")
        #expect(output == .fail("No value at key token 'nonExistent'"))
    }

    @Test
    func testGetInvalidPath_emptyKey() async {
        let output = await runCmd("config --get ''")
        #expect(output == .fail("Invalid empty key"))
    }

    @Test
    func testGetInvalidPath_doubleDot() async {
        let output = await runCmd("config --get a..b")
        #expect(output == .fail("Invalid key 'a..b'"))
    }

    @Test
    func testGetInvalidPath_trailingDot() async {
        let output = await runCmd("config --get a.")
        #expect(output == .fail("Invalid key 'a.'"))
    }

    // The naturally-built configMap (buildConfigMap) never produces arrays, so the array branches
    // of OrderedJson.find/dumpAllKeysRecursive are exercised directly here.
    @Test
    func testFindArrayIndex_success() {
        let arr: OrderedJson = .array([.string("a"), .string("b")])
        #expect(arr.find(keyPath: ["1"].slice) == .success(.string("b")))
    }

    @Test
    func testFindArrayIndex_outOfBounds() {
        let arr: OrderedJson = .array([.string("a")])
        #expect(arr.find(keyPath: ["5"].slice) == .failure("Index out of bounds. Index: 5, Size: 1"))
    }

    @Test
    func testFindArrayIndex_notInt() {
        let arr: OrderedJson = .array([.string("a")])
        #expect(arr.find(keyPath: ["foo"].slice) == .failure("Can't convert key token 'foo' to Int"))
    }

    @Test
    func testDumpAllKeys_array() {
        let value: OrderedJson = .array([.string("a"), .dict(["k": .int(1)])])
        var result: [String] = []
        value.dumpAllKeysRecursive(path: ".", result: &result)
        #expect(result == [".", "0", "1", "1.k"])
    }

    @Test
    func testGetMode_json_literal() async {
        let command = parseCommand("focus left").cmdOrDie
        let binding = HotkeyBinding(.option, .h, command)
        let binding2 = HotkeyBinding(.option, .j, parseCommand("focus down").cmdOrDie)
        config.modes = ["main": Mode(bindings: [binding.descriptionWithKeyCode: binding, binding2.descriptionWithKeyCode: binding2])]

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
        #expect(output == CmdOutput(stdout: [expected]))
    }

    @Test
    func testGetRoot_json_literal() async {
        config.modes = ["main": Mode(bindings: [:])]
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
        #expect(output == CmdOutput(stdout: [expected]))
    }

    @Test
    func testGetMode_keysJson_literal() async {
        config.modes = ["main": Mode(bindings: [:])]
        let output = await runCmd("config --get mode.main --keys --json")
        #expect(output == CmdOutput(stdout: ["[\n  \"binding\"\n]"]))
    }

    @Test
    func testGetScalar_json_literal() async {
        bindAltHToFocusLeft()
        let output = await runCmd("config --get mode.main.binding.alt-h --json")
        #expect(output == CmdOutput(stdout: ["\"focus left\""]))
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
        #expect(JSONEncoder.aeroSpaceDefault.encodeToString(value) == expected)
    }

    /// Binds alt-h to `focus left` in the main mode, and returns that command
    @discardableResult
    private func bindAltHToFocusLeft() -> Shell<any Command> {
        let command = parseCommand("focus left").cmdOrDie
        let binding = HotkeyBinding(.option, .h, command)
        config.modes = ["main": Mode(bindings: [binding.descriptionWithKeyCode: binding])]
        return command
    }
}

/// Enough modes that a dictionary order can't match the sorted order by chance
private let manyModeNames = ["main", "service", "resize", "move", "a", "z", "b", "y", "c", "x"]

private func manyModes(bindings: [String: HotkeyBinding] = [:]) -> [String: Mode] {
    Dictionary(uniqueKeysWithValues: manyModeNames.map { ($0, Mode(bindings: bindings)) })
}
