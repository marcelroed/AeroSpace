@testable import AppBundle
import Common
import Foundation
import HotKey
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct ConfigCommandTest: AeroSpaceTestSuite {
    @Test
    func testParse() {
        assertNil(parseCommand("config --major-keys").errorOrNil)
        assertNil(parseCommand("config --all-keys").errorOrNil)
        assertNil(parseCommand("config --config-path").errorOrNil)
        assertNil(parseCommand("config --get foo").errorOrNil)
        assertNil(parseCommand("config --get foo --keys").errorOrNil)
        assertNil(parseCommand("config --get foo --json").errorOrNil)
        assertNil(parseCommand("config --get foo --keys --json").errorOrNil)

        assertEquals(
            parseCommand("config").errorOrNil,
            "Mandatory flag is not specified (--get|--major-keys|--all-keys|--config-path)",
        )
        // --keys/--json alone still trigger the mandatory-flag check first because they don't
        // contribute to the mandatory-flag set.
        assertEquals(
            parseCommand("config --keys").errorOrNil,
            "Mandatory flag is not specified (--get|--major-keys|--all-keys|--config-path)",
        )
        assertEquals(
            parseCommand("config --json").errorOrNil,
            "Mandatory flag is not specified (--get|--major-keys|--all-keys|--config-path)",
        )
        assertEquals(parseCommand("config --major-keys --keys").errorOrNil, "--keys flag requires --get flag")
        assertEquals(parseCommand("config --major-keys --json").errorOrNil, "--json flag requires --get flag")

        // Two mandatory flags are mutually exclusive. The collection of conflicting flag names
        // comes from a Set so we can't rely on the order, only the message shape.
        let conflictErr = parseCommand("config --major-keys --all-keys").errorOrNil
        assertTrue(conflictErr?.hasPrefix("Conflicting flags are specified:") == true)
        assertTrue(conflictErr?.contains("--major-keys") == true)
        assertTrue(conflictErr?.contains("--all-keys") == true)
    }

    @Test
    func testConfigPath() async {
        await assertRun("config --config-path", exitCode: 0, stdout: [configUrl.absoluteURL.path], stderr: [])
    }

    @Test
    func testMajorKeys() async {
        config.modes = [
            "main": Mode(bindings: [:]),
            "service": Mode(bindings: [:]),
        ]
        let result = await assertRun("config --major-keys", exitCode: 0, stderr: [])
        // The whole listing comes back as one stdout entry separated by newlines.
        // Dict iteration order isn't stable, so sort before asserting.
        let lines = (result.stdout.singleOrNil() ?? "").split(separator: "\n").map(String.init).sorted()
        assertEquals(lines, [".", "mode", "mode.main.binding", "mode.service.binding"])
    }

    @Test
    func testAllKeys() async {
        bindAltHToFocusLeft()

        // Single mode + single binding => dict iteration order doesn't affect the output.
        await assertRun("config --all-keys", exitCode: 0, stdout: [".\nmode\nmode.main\nmode.main.binding\nmode.main.binding.alt-h"], stderr: [])
    }

    @Test
    func testGetRoot_complexObject_fails() async {
        await assertRun(
            "config --get .",
            exitCode: 2,
            stdout: [],
            stderr: ["Complicated objects can be printed only with --json flag. Alternatively, you can try to inspect keys of the object with --keys flag"],
        )
    }

    @Test
    func testGetRoot_keys() async {
        config.modes = ["main": Mode(bindings: [:])]
        await assertRun("config --get . --keys", exitCode: 0, stdout: ["mode"], stderr: [])
    }

    @Test
    func testGetRoot_json() async {
        config.modes = ["main": Mode(bindings: [:])]
        let expectedMap: OrderedJson = .dict(["mode": .dict(["main": .dict(["binding": .dict([:])])])])
        let expectedJson = JSONEncoder.aeroSpaceDefault.encodeToString(expectedMap)

        await assertRun("config --get . --json", exitCode: 0, stdout: [expectedJson.orDie()], stderr: [])
    }

    @Test
    func testGetRoot_keysJson() async {
        config.modes = ["main": Mode(bindings: [:])]
        // --keys converts the map into an array of string-scalar keys, which is then JSON-encoded.
        let expected = JSONEncoder.aeroSpaceDefault.encodeToString(
            OrderedJson.array([.string("mode")]),
        )

        await assertRun("config --get . --keys --json", exitCode: 0, stdout: [expected.orDie()], stderr: [])
    }

    @Test
    func testGetMode_keys_sortedOutput() async {
        config.modes = [
            "main": Mode(bindings: [:]),
            "service": Mode(bindings: [:]),
        ]
        // Plain (non-json) array output is sorted before printing.
        await assertRun("config --get mode --keys", exitCode: 0, stdout: ["main\nservice"], stderr: [])
    }

    @Test
    func testGetScalar() async {
        let command = bindAltHToFocusLeft()

        await assertRun("config --get mode.main.binding.alt-h", exitCode: 0, stdout: [command.shellOfCommandsDescription], stderr: [])
    }

    @Test
    func testGetScalar_keys_fails() async {
        let command = bindAltHToFocusLeft()

        // The error message interpolates the enum directly, yielding the default Swift case repr.
        await assertRun(
            "config --get mode.main.binding.alt-h --keys",
            exitCode: 2,
            stdout: [],
            stderr: ["--keys flag cannot be applied to scalar object 'string(\"\(command.shellOfCommandsDescription)\")'"],
        )
    }

    @Test
    func testGetScalar_dereference_fails() async {
        let command = bindAltHToFocusLeft()

        await assertRun("config --get mode.main.binding.alt-h.foo", exitCode: 2, stdout: [], stderr: ["Can't dereference scalar value '\(command.shellOfCommandsDescription)'"])
    }

    @Test
    func testGetMissingKey_fails() async {
        await assertRun("config --get nonExistent", exitCode: 2, stdout: [], stderr: ["No value at key token 'nonExistent'"])
    }

    @Test
    func testGetInvalidPath_emptyKey() async {
        await assertRun("config --get ''", exitCode: 2, stdout: [], stderr: ["Invalid empty key"])
    }

    @Test
    func testGetInvalidPath_doubleDot() async {
        await assertRun("config --get a..b", exitCode: 2, stdout: [], stderr: ["Invalid key 'a..b'"])
    }

    @Test
    func testGetInvalidPath_trailingDot() async {
        await assertRun("config --get a.", exitCode: 2, stdout: [], stderr: ["Invalid key 'a.'"])
    }

    // The naturally-built configMap (buildConfigMap) never produces arrays, so the array branches
    // of OrderedJson.find/dumpAllKeysRecursive are exercised directly here.
    @Test
    func testFindArrayIndex_success() {
        let arr: OrderedJson = .array([.string("a"), .string("b")])
        assertSucc(arr.find(keyPath: ["1"].slice), .string("b"))
    }

    @Test
    func testFindArrayIndex_outOfBounds() {
        let arr: OrderedJson = .array([.string("a")])
        assertFail(arr.find(keyPath: ["5"].slice), "Index out of bounds. Index: 5, Size: 1")
    }

    @Test
    func testFindArrayIndex_notInt() {
        let arr: OrderedJson = .array([.string("a")])
        assertFail(arr.find(keyPath: ["foo"].slice), "Can't convert key token 'foo' to Int")
    }

    @Test
    func testDumpAllKeys_array() {
        let value: OrderedJson = .array([.string("a"), .dict(["k": .int(1)])])
        var result: [String] = []
        value.dumpAllKeysRecursive(path: ".", result: &result)
        assertEquals(result, [".", "0", "1", "1.k"])
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
        await assertRun("config --get mode --json", exitCode: 0, stdout: [expected], stderr: [])
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
        await assertRun("config --get . --json", exitCode: 0, stdout: [expected], stderr: [])
    }

    @Test
    func testGetMode_keysJson_literal() async {
        config.modes = ["main": Mode(bindings: [:])]
        await assertRun("config --get mode.main --keys --json", exitCode: 0, stdout: ["[\n  \"binding\"\n]"], stderr: [])
    }

    @Test
    func testGetScalar_json_literal() async {
        bindAltHToFocusLeft()
        await assertRun("config --get mode.main.binding.alt-h --json", exitCode: 0, stdout: ["\"focus left\""], stderr: [])
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
        assertEquals(JSONEncoder.aeroSpaceDefault.encodeToString(value), expected)
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
