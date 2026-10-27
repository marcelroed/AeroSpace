@testable import AppBundle
import Common
import Testing

/// The errors that `parseCommand` and `ArgCursor` report for every subcommand. Parsing stops at the first error
@Suite
struct GenericParseErrorTest {
    @Test(arguments: parseFailures)
    func testParseFailure(command: String, msg: String) {
        expectEqual(parseCommand(command).errorOrNil, msg)
    }

    @Test
    func testEmptyCommand() {
        expectEqual(parseWords([]), .invalid("Can't parse empty string command"))
        expectEqual(parseWords([""]), .invalid("Can't parse empty string command"))
        expectEqual(parseCommand("''").errorOrNil, "Can't parse empty string command")
    }

    @Test
    func testUnrecognizedSubcommand() {
        expectEqual(parseCommand("bogus").errorOrNil, "Unrecognized subcommand 'bogus'")
        expectEqual(parseCommand("--help").errorOrNil, "Unrecognized subcommand '--help'")
        expectEqual(parseWords(["bogus", "--help"]), .invalid("Unrecognized subcommand 'bogus'"))
    }

    @Test
    func testHelpWinsOverParseErrors() {
        for args in [["--window-id", "abc", "--help"], ["--window-id", "1", "--window-id", "2", "-h"], ["--bogus", "--help"], ["foo", "--help"]] {
            expectEqual(parseWords(["close"] + args), .help(.close), "\(args)")
        }
        // After '--', '--help' is an argument
        expectEqual(parseWords(["close", "--", "--help"]), .invalid("Unknown argument '--help'"))
    }

    @Test
    func testDoubleDashWithoutArgs() {
        #expect(parseCommand("close --").cmdOrNil != nil)
        expectEqual(parsedCmd("layout tiles --", as: LayoutCommand.self).map { Array($0.toggleBetween) }, [.tiles])
        expectEqual(parsedCmd("layout tiles -- tiling", as: LayoutCommand.self).map { Array($0.toggleBetween) }, [.tiles, .tiling])
    }
}

private func parseWords(_ words: [String]) -> CmdParseError? {
    Result { () throws(CmdParseError) in try parseCommand(words) }.failureOrNil
}

nonisolated private let layoutPossibleValues = "(accordion|tiles|horizontal|vertical|h_accordion|v_accordion|h_tiles|v_tiles|tiling|floating)"

nonisolated private let parseFailures: [(command: String, msg: String)] = [
    // The first unknown flag
    ("close --bogus", "Unknown flag '--bogus'"),
    ("close --bogus --also-bogus", "Unknown flag '--bogus'"),
    ("split --bogus", "Unknown flag '--bogus'"),
    ("list-windows --all --focused --bogus", "Unknown flag '--bogus'"),
    // Options come before positional args are checked
    ("close foo --bogus", "Unknown flag '--bogus'"),

    // Negative numbers are positional args
    ("close -10", "Unknown argument '-10'"),

    // Flag values
    ("close --window-id", "'--window-id' must be followed by '<window-id>'"),
    ("close --window-id --quit-if-last-window --bogus", "'--window-id' must be followed by '<window-id>'"),
    ("close --window-id abc", "Failed to parse 'abc' CLI argument: Can't convert 'abc' to UInt32"),
    ("close --window-id abc foo", "Failed to parse 'abc' CLI argument: Can't convert 'abc' to UInt32"),
    ("focus --boundaries foo left", "Can't parse 'foo'.\nPossible values: (workspace|all-monitors-outer-frame)"),

    // Duplicated option
    ("close --window-id 1 --window-id 2", "Duplicated option '--window-id'"),
    ("close --quit-if-last-window --quit-if-last-window", "Duplicated option '--quit-if-last-window'"),
    ("close --window-id 1 --window-id", "Duplicated option '--window-id'"),
    ("close --window-id 1 --window-id 2 foo", "Duplicated option '--window-id'"),

    // Unknown argument
    ("close foo", "Unknown argument 'foo'"),
    ("close -- --bogus", "Unknown argument '--bogus'"),
    ("split foo bar", "Can't parse 'foo'.\nPossible values: (horizontal|vertical|opposite)"),

    // '--' ends the options, it isn't an argument
    ("layout foo", "Can't parse 'foo'\nPossible values: \(layoutPossibleValues)"),
    ("layout --", "Argument '\(layoutPossibleValues)' is mandatory"),
    ("layout -- -x", "Can't parse '-x'\nPossible values: \(layoutPossibleValues)"),
]
