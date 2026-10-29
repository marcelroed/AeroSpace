@testable import AppBundle
import Common
import Testing

@Suite
struct ShellParserTest {
    static let parseRows: [(label: String, input: String, shell: Shell<[String]>)] = [
        ("empty input", "", .empty),
        ("only blank lines and comments", " \t# a comment\n\n    # another\n", .empty),
        ("a command is its words", "foo bar baz", .cmd(["foo", "bar", "baz"])),
        ("empty quoted words are words", "echo '' \"\"", .cmd(["echo", "", ""])),
        ("leading blank lines and comments are skipped", "# comment\n\nfoo bar\n", .cmd("foo", "bar")),
        ("a chain nests to the left", "a && b && c", .and(.and("a", "b"), "c")),
        ("| binds tighter than &&, && tighter than ||", "a | b && c || d", .or(.and(.pipe("a", "b"), "c"), "d")),
        ("the same, with the tighter operators on the right", "a || b && c | d", .or("a", .and("b", .pipe("c", "d")))),
        ("; binds loosest", "a && b; c || d", .seq(.and("a", "b"), .or("c", "d"))),
        ("; and newlines separate commands, also repeated", "a;;b\n\nc;\nd", .seq(["a", "b", "c", "d"])),
        ("a trailing separator is allowed", "foo;\n\n;\n", "foo"),
        ("parens group", "(a || b) && (c || d)", .and(.or("a", "b"), .or("c", "d"))),
        ("a group of one command is the command", "((foo bar))", .cmd("foo", "bar")),
        ("a group may span lines", "a && ( # comment\n\n  b\n  c\n)", .and("a", .seq("b", "c"))),
        ("a group may follow a separator", "a\n(b; c)", .seq("a", .seq("b", "c"))),
    ]

    // `await`: the rows hold AppBundle types, which are MainActor-isolated, and the arguments are evaluated off the main actor
    @Test(arguments: await parseRows)
    func parses(label: String, input: String, shell: Shell<[String]>) {
        expectEqual(parse(input), .success(shell), Comment(rawValue: label))
    }

    @Test(arguments: [
        ("an operator needs a right operand", "foo && || bar", "Line 1 Column 8: Expected at least one word. Got: ||"),
        ("an operator needs a left operand", "&& foo", "Line 1 Column 1: Expected at least one word. Got: &&"),
        ("; needs a left operand", "\n;", "Line 2 Column 1: Expected at least one word. Got: ;"),
        ("a newline before an operator must be escaped", "echo foo\n  || bar", "Line 1 Column 9: Please escape newline with backslash character."),
        ("a newline after an operator must be escaped", "foo ||\n    bar", "Line 1 Column 7: Please escape newline with backslash character."),
        ("a group can't be empty", "(\n)", "Line 2 Column 1: Expected at least one word. Got: )"),
        ("an unclosed paren", "(foo", "Line 1 Column 5: Expected ')'. Got: 'End of input'"),
        ("an unopened paren", "foo)", "Line 1 Column 4: Unexpected token ')'"),
        ("a group can't be piped", "(foo) | bar", "Line 1 Column 7: Unexpected token '|'"),
        ("a group can't take words", "(foo) bar", "Line 1 Column 7: Unexpected token 'bar'"),
        ("a command can't take a group", "foo (bar)", "Line 1 Column 5: Unexpected token '('"),
    ] as [(String, String, String)])
    func parseFails(label: String, input: String, message: String) {
        expectEqual(parse(input), .failure(.invalid(message)), Comment(rawValue: label))
    }

    static let descriptionRows: [(label: String, shell: Shell<[String]>, description: String)] = [
        ("operands of higher precedence need no parens", .or(.and("a", "b"), .pipe("c", "d")), "a && b || c | d"),
        ("operands of lower precedence get parens", .and(.or("a", "b"), .or("c", "d")), "(a || b) && (c || d)"),
        ("a ; operand gets parens", .or(.seq("a", "b"), "c"), "(a; b) || c"),
        ("a chain of one operator needs no parens", .and(["a", "b", "c"]), "a && b && c"),
        ("empty", .empty, ""),
    ]

    @Test(arguments: await descriptionRows)
    func buildDescription(label: String, shell: Shell<[String]>, description: String) {
        expectEqual(shell.buildDescription { $0.joined(separator: " ") }, description, Comment(rawValue: label))
    }
}

extension Shell {
    static func or(_ a: Self, _ b: Self) -> Self { .or([a, b]) }
    static func and(_ a: Self, _ b: Self) -> Self { .and([a, b]) }
    static func pipe(_ a: Self, _ b: Self) -> Self { .pipe([a, b]) }
    static func seq(_ a: Self, _ b: Self) -> Self { .seq([a, b]) }

    static func cmd(_ a: String, _ b: String) -> Self where T == [String] { .cmd([a, b]) }
}

extension Shell: ExpressibleByUnicodeScalarLiteral where T == [String] {}
extension Shell: ExpressibleByExtendedGraphemeClusterLiteral where T == [String] {}
extension Shell: ExpressibleByStringLiteral where T == [String] {
    public init(stringLiteral value: String) { self = .cmd([value]) }
}

private func parse(_ raw: String) -> Result<Shell<[String]>, CmdParseError> {
    Result { () throws(CmdParseError) in try raw.lexAndParseShell() }
}
