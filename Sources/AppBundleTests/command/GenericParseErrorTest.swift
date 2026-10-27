@testable import AppBundle
import Common
import Testing

/// The errors that `parseCmdArgs` and `parseSpecificCmdArgs` report for every subcommand, and how they are joined
@Suite
struct GenericParseErrorTest: AeroSpaceTestSuite {
    @Test(arguments: parseFailures)
    func testParseFailure(command: String, msg: String) {
        testParseCommandFail(command, msg: msg)
    }

    @Test
    func testEmptyCommand() {
        assertEquals(parseCmdArgs([String]().slice).failureOrNil, CmdParsingFailure("Can't parse empty string command", 2))
        assertEquals(parseCmdArgs([""].slice).failureOrNil, CmdParsingFailure("Can't parse empty string command", 2))
        testParseCommandFail("''", msg: "Can't parse empty string command")
    }

    @Test
    func testUnrecognizedSubcommand() {
        testParseCommandFail("bogus", msg: "Unrecognized subcommand 'bogus'")
        testParseCommandFail("--help", msg: "Unrecognized subcommand '--help'")
        assertEquals(parseCmdArgs(["bogus", "--help"].slice).failureOrNil, CmdParsingFailure("Unrecognized subcommand 'bogus'", 2))
    }

    @Test
    func testHelpWinsOverEarlierErrors() {
        let help = "USAGE: close [-h|--help] [--quit-if-last-window] [--window-id <window-id>]"
        assertEquals(parseCmdArgs(["close", "--window-id", "abc", "--help"].slice).helpOrNil, help)
        assertEquals(parseCmdArgs(["close", "--window-id", "1", "--window-id", "2", "-h"].slice).helpOrNil, help)
        // But not over an unknown flag or argument, which stops the parsing
        assertEquals(parseCmdArgs(["close", "--bogus", "--help"].slice).helpOrNil, nil)
        assertEquals(parseCmdArgs(["close", "foo", "--help"].slice).helpOrNil, nil)
    }
}

private let layoutPossibleValues = "(accordion|tiles|horizontal|vertical|h_accordion|v_accordion|h_tiles|v_tiles|tiling|floating)"

private let parseFailures: [(command: String, msg: String)] = [
    // Unknown flag stops the parsing
    ("close --bogus", "ERROR: Unknown flag '--bogus'"),
    ("close --bogus --also-bogus", "ERROR: Unknown flag '--bogus'"),
    ("close -10", "ERROR: Unknown flag '-10'"), // Negative numbers are positional only for resize
    ("split --bogus", "ERROR: Unknown flag '--bogus'\nERROR: Argument '(horizontal|vertical|opposite)' is mandatory"),
    ("list-windows --all --focused --bogus", "ERROR: Unknown flag '--bogus'\nERROR: Conflicting options: --all, --focused"),

    // Flag values
    ("close --window-id", "ERROR: '--window-id' must be followed by '<window-id>'"),
    ("close --window-id --quit-if-last-window --bogus", "ERROR: '--window-id' must be followed by '<window-id>'\nERROR: Unknown flag '--bogus'"),
    ("close --window-id abc", "ERROR: Failed to parse 'abc' CLI argument: Can't convert 'abc' to UInt32"),
    ("close --window-id abc foo", "ERROR: Failed to parse 'abc' CLI argument: Can't convert 'abc' to UInt32\nERROR: Unknown argument 'foo'"),
    ("focus --boundaries foo left", "ERROR: Can't parse 'foo'.\n       Possible values: (workspace|all-monitors-outer-frame)"),

    // Duplicated option doesn't stop the parsing
    ("close --window-id 1 --window-id 2", "ERROR: Duplicated option '--window-id'"),
    ("close --quit-if-last-window --quit-if-last-window", "ERROR: Duplicated option '--quit-if-last-window'"),
    ("close --window-id 1 --window-id", "ERROR: Duplicated option '--window-id'\nERROR: '--window-id' must be followed by '<window-id>'"),
    ("close --window-id 1 --window-id 2 foo", "ERROR: Duplicated option '--window-id'\nERROR: Unknown argument 'foo'"),

    // Unknown argument stops the parsing
    ("close foo", "ERROR: Unknown argument 'foo'"),
    ("close foo --bogus", "ERROR: Unknown argument 'foo'"),
    ("close --", "ERROR: Unknown argument '--'"),
    ("split foo bar", "ERROR: Can't parse 'foo'.\n       Possible values: (horizontal|vertical|opposite)\nERROR: Unknown argument 'bar'"),

    // layout passes '--' to its <layout> parser
    ("layout foo", "ERROR: Can't parse 'foo'\n       Possible values: \(layoutPossibleValues)"),
    ("layout --", "ERROR: Can't parse '--'\n       Possible values: \(layoutPossibleValues)"),
    ("layout -- -x", "ERROR: Can't parse '--'\n       Possible values: \(layoutPossibleValues)\nERROR: Unknown argument '-x'"),
    ("layout tiles --", "ERROR: Can't parse '--'\n       Possible values: \(layoutPossibleValues)"),
    ("layout tiles -- tiling", "ERROR: Can't parse '--'\n       Possible values: \(layoutPossibleValues)\nERROR: Unknown argument 'tiling'"),
]
