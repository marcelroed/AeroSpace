@testable import AppBundle
import Common
import Testing

@Suite
struct ShellParserTest {
    @Test
    func testParser() {
        expectEqual(shell("echo foo && bar"), .success(.and(.cmd("echo", "foo"), "bar")))
        expectEqual(shell("foo && bar || baz"), .success(.or(.and("foo", "bar"), "baz")))
        expectEqual(shell("foo || bar && baz"), .success(.or("foo", .and("bar", "baz"))))
        expectEqual(shell("echo '' \"\""), .success(.cmd(["echo", "", ""])))

        let a = """
            foo ||
                bar
            """
        expectEqual(shell(a), .failure("Line 1 Column 7: Expected at least one word. Got: \n"))
        let b = """
            foo
                || bar
            """
        expectEqual(shell(b), .failure("Line 1 Column 4: Please escape newline with backslash character."))
        let c = """
            foo || \\
                bar || \\ # comment
                baz \\
                || duh \\ # comment
                || qux
            """
        expectEqual(shell(c), .success(.or(["foo", "bar", "baz", "duh", "qux"])))
    }

    @Test
    func testParserEmpty() {
        expectEqual(shell(""), .success(.empty))
        expectEqual(shell("   "), .success(.empty))
        expectEqual(shell("\t"), .success(.empty))
        expectEqual(shell("# only a comment"), .success(.empty))
    }

    @Test
    func testParserOnlyNewlinesAndComments() {
        expectEqual(shell("\n"), .success(.empty))
        expectEqual(shell("\n\n"), .success(.empty))
        expectEqual(shell("# only a comment\n"), .success(.empty))
        expectEqual(shell("    # first comment\n    # second comment\n"), .success(.empty))
        expectEqual(shell("# comment\nfoo"), .success("foo"))
        expectEqual(shell("\n\nfoo bar\n"), .success(.cmd("foo", "bar")))
        expectEqual(shell("\n;"), .failure("Line 2 Column 1: Expected at least one word. Got: ;"))
    }

    @Test
    func testParserSingleCommand() {
        expectEqual(shell("foo"), .success("foo"))
        expectEqual(shell("foo bar"), .success(.cmd("foo", "bar")))
        expectEqual(shell("foo bar baz"), .success(.cmd(["foo", "bar", "baz"])))
    }

    @Test
    func testParserPipe() {
        expectEqual(shell("foo | bar"), .success(.pipe("foo", "bar")))
        expectEqual(shell("a | b | c"), .success(.pipe(["a", "b", "c"])))
        expectEqual(shell("a b | c d"), .success(.pipe(.cmd("a", "b"), .cmd("c", "d"))))
    }

    @Test
    func testParserAndChain() {
        expectEqual(shell("a && b && c"), .success(.and(["a", "b", "c"])))
    }

    @Test
    func testParserOrChain() {
        expectEqual(shell("a || b || c"), .success(.or(["a", "b", "c"])))
    }

    @Test
    func testParserPrecedence() {
        expectEqual(shell("a | b && c"), .success(.and(.pipe("a", "b"), "c")))
        expectEqual(shell("a && b | c"), .success(.and("a", .pipe("b", "c"))))
        expectEqual(shell("a | b || c"), .success(.or(.pipe("a", "b"), "c")))
        expectEqual(shell("a || b | c"), .success(.or("a", .pipe("b", "c"))))
        expectEqual(shell("a | b && c || d"), .success(.or(.and(.pipe("a", "b"), "c"), "d")))
    }

    @Test
    func testParserSemicolon() {
        expectEqual(shell("foo; bar"), .success(.seq("foo", "bar")))
        expectEqual(shell("a;b"), .success(.seq("a", "b")))
        expectEqual(shell("a;;b"), .success(.seq("a", "b")))
        expectEqual(shell("a; b; c"), .success(.seq(["a", "b", "c"])))
        expectEqual(shell("a && b; c || d"), .success(.seq(.and("a", "b"), .or("c", "d"))))
        expectEqual(shell("a | b; c | d"), .success(.seq(.pipe("a", "b"), .pipe("c", "d"))))
    }

    @Test
    func testParserParens() {
        expectEqual(shell("(foo)"), .success("foo"))
        expectEqual(shell("(foo bar)"), .success(.cmd("foo", "bar")))
        expectEqual(shell("((foo))"), .success("foo"))
        expectEqual(shell("(a; b)"), .success(.seq("a", "b")))
        expectEqual(shell("(a && b) || c"), .success(.or(.and("a", "b"), "c")))
        expectEqual(shell("a && (b || c)"), .success(.and("a", .or("b", "c"))))
        expectEqual(shell("(a || b) && (c || d)"), .success(.and(.or("a", "b"), .or("c", "d"))))
    }

    @Test
    func testParserParensStartingWithNewlines() {
        expectEqual(shell("(\n  foo\n)"), .success("foo"))
        expectEqual(shell("( # comment\n  a;\n  b\n)"), .success(.seq("a", "b")))
        expectEqual(shell("a && (\n\n  b || c\n)"), .success(.and("a", .or("b", "c"))))
        expectEqual(shell("(\n)"), .failure("Line 2 Column 1: Expected at least one word. Got: )"))
    }

    @Test
    func testParserNewlineSeparatesCommands() {
        expectEqual(shell("foo\nbar"), .success(.seq("foo", "bar")))
        expectEqual(shell("foo bar;\nbaz"), .success(.seq(.cmd("foo", "bar"), "baz")))
        expectEqual(shell("a && b\n\n(c\nd) # comment\ne"), .success(.seq([.and("a", "b"), .seq("c", "d"), "e"])))
        expectEqual(shell("a\n&& b"), .failure("Line 1 Column 2: Please escape newline with backslash character."))
    }

    @Test
    func testParserTrailingOperator() {
        expectEqual(shell("foo;"), .success(.cmd("foo")))
        expectEqual(shell("foo\n\n"), .success(.cmd("foo")))
        expectEqual(shell("foo\n\n;\n"), .success(.cmd("foo")))

        expectEqual(shell("foo &&"), .failure("Line 1 Column 7: Expected at least one word. Got: End of input"))
        expectEqual(shell("foo ||"), .failure("Line 1 Column 7: Expected at least one word. Got: End of input"))
        expectEqual(shell("foo |"), .failure("Line 1 Column 6: Expected at least one word. Got: End of input"))
    }

    @Test
    func testParserFailLeadingOperator() {
        expectEqual(shell("&& foo"), .failure("Line 1 Column 1: Expected at least one word. Got: &&"))
        expectEqual(shell("|| foo"), .failure("Line 1 Column 1: Expected at least one word. Got: ||"))
        expectEqual(shell("| foo"), .failure("Line 1 Column 1: Expected at least one word. Got: |"))
        expectEqual(shell(";"), .failure("Line 1 Column 1: Expected at least one word. Got: ;"))
    }

    @Test
    func testParserFailParens() {
        expectEqual(shell("()"), .failure("Line 1 Column 2: Expected at least one word. Got: )"))
        expectEqual(shell("(foo"), .failure("Line 1 Column 5: Expected ')'. Got: 'End of input'"))
        expectEqual(shell("foo)"), .failure("Line 1 Column 4: Unexpected token ')'"))
        // Per the grammar, a parenthesized group is a Pipe-level atom and cannot itself be piped.
        expectEqual(shell("(foo) | bar"), .failure("Line 1 Column 7: Unexpected token '|'"))
    }

    @Test
    func testBuildDescription() {
        func render(_ shell: Shell<[String]>) -> String { shell.buildDescription { $0.joined(separator: " ") } }

        expectEqual(render(.or(.and("a", "b"), "c")), "a && b || c")
        expectEqual(render(.seq(.or("a", "b"), .and("c", "d"))), "a || b; c && d")
        expectEqual(render(.and(.pipe("a", "b"), "c")), "a | b && c")

        expectEqual(render(.and(.or("a", "b"), "c")), "(a || b) && c")
        expectEqual(render(.and("a", .or("b", "c"))), "a && (b || c)")
        expectEqual(render(.pipe(.seq("a", "b"), "c")), "(a; b) | c")
        expectEqual(render(.or(.seq("a", "b"), "c")), "(a; b) || c")
        expectEqual(render(.and(.or("a", "b"), .or("c", "d"))), "(a || b) && (c || d)")

        expectEqual(render("foo"), "foo")
        expectEqual(render(.and(["a", "b", "c"])), "a && b && c")
        #expect(render(.empty).isEmpty)
    }
}

extension Shell {
    static func or(_ a: Self, _ b: Self) -> Self { .or([a, b]) }
    static func and(_ a: Self, _ b: Self) -> Self { .and([a, b]) }
    static func pipe(_ a: Self, _ b: Self) -> Self { .pipe([a, b]) }
    static func seq(_ a: Self, _ b: Self) -> Self { .seq([a, b]) }

    static func cmd(_ a: String, _ b: String) -> Self where T == [String] { .cmd([a, b]) }
    static func cmd(_ a: String) -> Self where T == [String] { .cmd([a]) }
}

extension Shell: ExpressibleByUnicodeScalarLiteral where T == [String] {}
extension Shell: ExpressibleByExtendedGraphemeClusterLiteral where T == [String] {}
extension Shell: ExpressibleByStringLiteral where T == [String] {
    public init(stringLiteral value: String) { self = .cmd([value]) }
}

private func shell(_ raw: String) -> Result<Shell<[String]>, CmdParseError> {
    Result { () throws(CmdParseError) in try raw.lexAndParseShell() }
}
