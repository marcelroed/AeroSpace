@testable import AppBundle
import Common
import Foundation
import HotKey
import Testing

@Suite(.aeroSpaceGlobalState)
struct ConfigCommandTest {
    @Test(arguments: [
        ("config --major-keys", nil),
        ("config --all-keys", nil),
        ("config --config-path", nil),
        ("config --get foo", nil),
        ("config --get foo --keys", nil),
        ("config --get foo --json", nil),
        ("config --get foo --keys --json", nil),
        ("config", "Mandatory flag is not specified (--get|--major-keys|--all-keys|--config-path)"),
        // --keys and --json aren't mandatory flags, so the mandatory-flag check comes first
        ("config --keys", "Mandatory flag is not specified (--get|--major-keys|--all-keys|--config-path)"),
        ("config --json", "Mandatory flag is not specified (--get|--major-keys|--all-keys|--config-path)"),
        ("config --major-keys --keys", "--keys flag requires --get flag"),
        ("config --major-keys --json", "--json flag requires --get flag"),
    ] + conflictingFlags as [(String, String?)])
    func parse(args: String, error: String?) {
        expectEqual(parseCommand(args).errorOrNil, error)
    }

    @Test
    func testConfigPath() async {
        let output = await runCmd("config --config-path")
        expectEqual(output, CmdOutput(stdout: [world.configUrl.absoluteURL.path]))
    }

    /// The listings are sorted. The `--json` output stays literal: the Raycast extension parses it
    @Test(arguments: [
        (.manyModes, "config --major-keys", """
            .
            mode
            mode.a.binding
            mode.b.binding
            mode.c.binding
            mode.main.binding
            mode.move.binding
            mode.resize.binding
            mode.service.binding
            mode.x.binding
            mode.y.binding
            mode.z.binding
            """),
        (.manyModes, "config --all-keys", ([".", "mode"] + manyModeNames.sorted().flatMap { (mode: String) -> [String] in
            ["mode.\(mode)", "mode.\(mode).binding", "mode.\(mode).binding.alt-h", "mode.\(mode).binding.alt-j", "mode.\(mode).binding.alt-k"]
        }).joined(separator: "\n")),
        (.manyModes, "config --get mode --keys", "a\nb\nc\nmain\nmove\nresize\nservice\nx\ny\nz"),
        (.manyModes, "config --get mode --keys --json", """
            [
              "a",
              "b",
              "c",
              "main",
              "move",
              "resize",
              "service",
              "x",
              "y",
              "z"
            ]
            """),
        (.oneMode, "config --get . --keys", "mode"),
        (.oneMode, "config --get . --keys --json", "[\n  \"mode\"\n]"),
        (.oneMode, "config --get mode.main --keys --json", "[\n  \"binding\"\n]"),
        (.oneMode, "config --get mode.main.binding.alt-h", "focus left"),
        (.oneMode, "config --get mode.main.binding.alt-h --json", "\"focus left\""),
        (.oneMode, "config --get mode --json", """
            {
              "main" : {
                "binding" : {
                  "alt-h" : "focus left",
                  "alt-j" : "focus down"
                }
              }
            }
            """),
        (.oneMode, "config --get . --json", """
            {
              "mode" : {
                "main" : {
                  "binding" : {
                    "alt-h" : "focus left",
                    "alt-j" : "focus down"
                  }
                }
              }
            }
            """),
    ] as [(ConfigFixture, String, String)])
    func get(fixture: ConfigFixture, args: String, stdout: String) async {
        fixture.install()
        let output = await runCmd(args)
        expectEqual(output, CmdOutput(stdout: [stdout]))
    }

    @Test(arguments: [
        ("config --get .", "Complicated objects can be printed only with --json flag. Alternatively, you can try to inspect keys of the object with --keys flag"),
        ("config --get mode.main.binding.alt-h --keys", "--keys flag cannot be applied to scalar object 'focus left'"),
        ("config --get mode.main.binding.alt-h.foo", "Can't dereference scalar value 'focus left'"),
        ("config --get nonExistent", "No value at key token 'nonExistent'"),
        ("config --get ''", "Invalid empty key"),
        ("config --get a..b", "Invalid key 'a..b'"),
        ("config --get a.", "Invalid key 'a.'"),
    ] as [(String, String)])
    func getFails(args: String, error: String) async {
        ConfigFixture.oneMode.install()
        let output = await runCmd(args)
        expectEqual(output, .fail(error))
    }
}

nonisolated enum ConfigFixture: Sendable {
    /// alt-h and alt-j in the main mode
    case oneMode
    /// Enough modes that a dictionary order can't match the sorted order by chance (RB-13), each with alt-h, alt-j and alt-k
    case manyModes

    @MainActor
    func install() {
        switch self {
            case .oneMode:
                let bindings = [HotkeyBinding(.option, .h, parseCommand("focus left").cmdOrDie), HotkeyBinding(.option, .j, parseCommand("focus down").cmdOrDie)]
                world.config.modes = [mainModeId: Mode(bindings: Dictionary(uniqueKeysWithValues: bindings.map { ($0.descriptionWithKeyCode, $0) }))]
            case .manyModes:
                let command = parseCommand("focus left").cmdOrDie
                let bindings = [HotkeyBinding(.option, .k, command), HotkeyBinding(.option, .h, command), HotkeyBinding(.option, .j, command)]
                let mode = Mode(bindings: Dictionary(uniqueKeysWithValues: bindings.map { ($0.descriptionWithKeyCode, $0) }))
                world.config.modes = Dictionary(uniqueKeysWithValues: manyModeNames.map { ($0, mode) })
        }
    }
}

nonisolated private let manyModeNames = ["main", "service", "resize", "move", "a", "z", "b", "y", "c", "x"]

/// Every combination of two or more mandatory flags, passed in reverse order. The flags used to be collected in a Set,
/// whose order is random. The eleven combinations make an unordered collection fail reliably (RB-13)
nonisolated private let conflictingFlags: [(String, String?)] = {
    let flags: [(name: String, args: String)] =
        [("--get", "--get foo"), ("--major-keys", "--major-keys"), ("--all-keys", "--all-keys"), ("--config-path", "--config-path")]
    return (0 ..< (1 << flags.count)).filter { $0.nonzeroBitCount >= 2 }.map { (mask: Int) -> (String, String?) in
        let combination = flags.indices.filter { mask & (1 << $0) != 0 }.map { flags[$0] }
        return ("config " + combination.reversed().map(\.args).joined(separator: " "), "Conflicting flags are specified: " + combination.map(\.name).joined(separator: ", "))
    }
}()
