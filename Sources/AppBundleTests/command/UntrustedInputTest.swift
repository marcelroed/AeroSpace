@testable import AppBundle
import Common
import Testing

/// The server parses and runs whatever a CLI request holds. No input may crash AeroSpace.app: a trap in a parser or in a
/// command body takes the window manager down
@Suite(.aeroSpaceGlobalState)
struct UntrustedInputTest {
    nonisolated static let extremeNumbers: [String] = [
        "0", "-1", "\(Int.min)", "\(Int64(Int32.max) + 1)", "\(Int.max)", "\(UInt64(Int.max) + 1)", "99999999999999999999999999999",
    ]

    /// Every numeric option and argument, `{}` is the number. `volume` is in `volumeNumbers`: running it would change
    /// the volume of the machine
    nonisolated static let numericArgs: [String] = [
        "balance-sizes --workspace {}",
        "close --window-id {}",
        "debug-windows --window-id {}",
        "echo --window-id {} x",
        "flatten-workspace-tree --workspace {}",
        "focus --dfs-index {}",
        "focus --window-id {}",
        "focus-monitor {}",
        "focus-monitor -- {}",
        "fullscreen --window-id {}",
        "join-with --window-id {} left",
        "layout --window-id {} tiling",
        "layout --workspace {} --root tiles",
        "list-windows --monitor {}",
        "list-windows --monitor 1 {}",
        "list-windows --pid {}",
        "list-windows --workspace {}",
        "list-workspaces --monitor {}",
        "macos-native-fullscreen --window-id {}",
        "macos-native-minimize --window-id {}",
        "move --window-id {} left",
        "move-node-to-monitor {}",
        "move-node-to-monitor --window-id {} next",
        "move-node-to-workspace {}",
        "move-node-to-workspace --window-id {} w",
        "move-workspace-to-monitor {}",
        "move-workspace-to-monitor --workspace {} next",
        "resize --window-id {} width 10",
        "resize width {}",
        "resize smart +{}",
        "resize smart-opposite -{}",
        "run-callback --window-id {} on-window-detected",
        "split --window-id {} opposite",
        "summon-workspace {}",
        "swap --window-id {} left",
        "test %{window-id} = {}",
        "test %{app-pid} = {}",
        "workspace {}",
        "workspace -- {}",
    ]

    @Test(arguments: numericArgs, extremeNumbers)
    func extremeNumbersDontCrash(template: String, number: String) async {
        setUpTree("h_tiles(*1 2 v_tiles(3 4))")
        _ = await runCliArgs(template.split(separator: " ").map { $0 == "{}" ? number : String($0) })
    }

    @Test(arguments: extremeNumbers)
    func volumeNumbersDontCrash(number: String) {
        let expected: VolumeCommand.VolumeAction? = Int(number).flatMap { (0 ... 100).contains($0) ? .set($0) : nil }
        expectEqual(parsedCmd("volume set \(number)", as: VolumeCommand.self)?.action, expected)
    }

    @Test(arguments: ["-9223372036854775808", "-1", "0"])
    func monitorIdBelowOneIsRejected(id: String) async {
        let message = "Monitor IDs use 1-based indexing. Values less than 1 are illegal"
        let windows = await runCliArgs(["list-windows", "--monitor", id])
        expectEqual(windows, .fail(message))
        let workspaces = await runCliArgs(["list-workspaces", "--monitor", id])
        expectEqual(workspaces, .fail(message))
    }

    @Test
    func deeplyNestedParenthesesAreRejected() async {
        let depth = 100_000 // Overflows the stack of the parser
        let output = await runCliArgs(["eval", String(repeating: "(", count: depth) + "true" + String(repeating: ")", count: depth)])
        expectEqual(output, .fail("Line 1 Column \(maxShellGroupNesting + 1): Parentheses are nested deeper than \(maxShellGroupNesting) levels"))
    }

    @Test
    func longChainIsRejected() async {
        // A chain nests to the left, so everything that walks a long one overflows the stack (in a debug build, run at
        // ~20k operators and deinit at ~50k). The limit stops the lexing too: the unclosed quote at the end isn't reached
        let chain: String = Array(repeating: "true", count: 100_000).joined(separator: " && ") + " '"
        let output = await runCliArgs(["eval", chain])
        let column = (maxShellOperators + 1) * "true && ".count - 2
        expectEqual(output, .fail("Line 1 Column \(column): More than \(maxShellOperators) operators in one expression"))
    }

    @Test
    func expressionAtTheLimitsRuns() async {
        let nested = String(repeating: "(", count: maxShellGroupNesting) + "echo a" + String(repeating: ")", count: maxShellGroupNesting)
        let nestedOutput = await runCliArgs(["eval", nested])
        expectEqual(nestedOutput, CmdOutput(stdout: ["a"]))
        let chain = Array(repeating: "true", count: maxShellOperators).joined(separator: " && ") + " && echo b"
        let chainOutput = await runCliArgs(["eval", chain])
        expectEqual(chainOutput, CmdOutput(stdout: ["b"]))
    }

    /// A config file is input too. An array of commands nests to the left like a chain
    static let tooManyOperatorsInArray: String =
        "[ERROR] mode.main.binding.alt-a: More than \(maxShellOperators) operators in one expression (an array of N commands joins them with N - 1 ';')"

    @Test
    func longConfigArrayOfCommandsIsRejected() {
        // 40k commands overflowed the stack of the config load, 20k the stack of `config --get`
        let commands: String = Array(repeating: "'focus left'", count: 50000).joined(separator: ", ")
        let errors: [String] = parseConfig("mode.main.binding.alt-a = [\(commands)]").strErrors
        expectEqual(errors, [Self.tooManyOperatorsInArray])
    }

    @Test
    func configArrayCountsTheOperatorsOfItsCommands() {
        let chain: String = Array(repeating: "focus left", count: maxShellOperators).joined(separator: " && ") // One below the limit
        let atLimit: [String] = parseConfig("mode.main.binding.alt-a = ['\(chain)', 'focus right']").strErrors
        expectEqual(atLimit, [])
        let overLimit: [String] = parseConfig("mode.main.binding.alt-a = ['\(chain)', 'focus right', 'focus up']").strErrors
        expectEqual(overLimit, [Self.tooManyOperatorsInArray])
    }

    @Test
    func longInterpolationTakesLinearTime() throws {
        // `echo`, `test`, `--format` and exec env tokenize at parse time, on the main thread. A quadratic tokenizer took 6.5 s for 1M chars
        let literal: String = String(repeating: "a%b%%", count: 100_000)
        let variable: String = String(repeating: "x", count: 500_000)
        var tokens: [InterToken<String>] = []
        let elapsed: Duration = try ContinuousClock().measure {
            tokens = try (literal + "%{\(variable)}").rawInterpolationTokens(interpolationChar: "%")
        }
        expectEqual(tokens, [.literal(literal), .interVar(variable)])
        #expect(elapsed < .seconds(1))
    }
}
