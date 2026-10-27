@testable import AppBundle
import Common
import Testing

@Suite
struct ShellParserTest {
    @Test
    func testParser() {
        #expect(shell("echo foo && bar") == .success(.and(.cmd("echo", "foo"), "bar")))
        #expect(shell("foo && bar || baz") == .success(.or(.and("foo", "bar"), "baz")))
        #expect(shell("foo || bar && baz") == .success(.or("foo", .and("bar", "baz"))))
        #expect(shell("echo '' \"\"") == .success(.cmd(["echo", "", ""])))

        let a = """
            foo ||
                bar
            """
        #expect(shell(a) == .failure("Line 1 Column 7: Expected at least one word. Got: \n"))
        let b = """
            foo
                || bar
            """
        #expect(shell(b) == .failure("Line 1 Column 4: Please escape newline with backslash character."))
        let c = """
            foo || \\
                bar || \\ # comment
                baz \\
                || duh \\ # comment
                || qux
            """
        #expect(shell(c) == .success(.or(["foo", "bar", "baz", "duh", "qux"])))
    }

    @Test
    func testParserEmpty() {
        #expect(shell("") == .success(.empty))
        #expect(shell("   ") == .success(.empty))
        #expect(shell("\t") == .success(.empty))
        #expect(shell("# only a comment") == .success(.empty))
    }

    @Test
    func testParserOnlyNewlinesAndComments() {
        #expect(shell("\n") == .success(.empty))
        #expect(shell("\n\n") == .success(.empty))
        #expect(shell("# only a comment\n") == .success(.empty))
        #expect(shell("    # first comment\n    # second comment\n") == .success(.empty))
        #expect(shell("# comment\nfoo") == .success("foo"))
        #expect(shell("\n\nfoo bar\n") == .success(.cmd("foo", "bar")))
        #expect(shell("\n;") == .failure("Line 2 Column 1: Expected at least one word. Got: ;"))
    }

    @Test
    func testParserSingleCommand() {
        #expect(shell("foo") == .success("foo"))
        #expect(shell("foo bar") == .success(.cmd("foo", "bar")))
        #expect(shell("foo bar baz") == .success(.cmd(["foo", "bar", "baz"])))
    }

    @Test
    func testParserPipe() {
        #expect(shell("foo | bar") == .success(.pipe("foo", "bar")))
        #expect(shell("a | b | c") == .success(.pipe(["a", "b", "c"])))
        #expect(shell("a b | c d") == .success(.pipe(.cmd("a", "b"), .cmd("c", "d"))))
    }

    @Test
    func testParserAndChain() {
        #expect(shell("a && b && c") == .success(.and(["a", "b", "c"])))
    }

    @Test
    func testParserOrChain() {
        #expect(shell("a || b || c") == .success(.or(["a", "b", "c"])))
    }

    @Test
    func testParserPrecedence() {
        #expect(shell("a | b && c") == .success(.and(.pipe("a", "b"), "c")))
        #expect(shell("a && b | c") == .success(.and("a", .pipe("b", "c"))))
        #expect(shell("a | b || c") == .success(.or(.pipe("a", "b"), "c")))
        #expect(shell("a || b | c") == .success(.or("a", .pipe("b", "c"))))
        #expect(shell("a | b && c || d") == .success(.or(.and(.pipe("a", "b"), "c"), "d")))
    }

    @Test
    func testParserSemicolon() {
        #expect(shell("foo; bar") == .success(.seq("foo", "bar")))
        #expect(shell("a;b") == .success(.seq("a", "b")))
        #expect(shell("a;;b") == .success(.seq("a", "b")))
        #expect(shell("a; b; c") == .success(.seq(["a", "b", "c"])))
        #expect(shell("a && b; c || d") == .success(.seq(.and("a", "b"), .or("c", "d"))))
        #expect(shell("a | b; c | d") == .success(.seq(.pipe("a", "b"), .pipe("c", "d"))))
    }

    @Test
    func testParserParens() {
        #expect(shell("(foo)") == .success("foo"))
        #expect(shell("(foo bar)") == .success(.cmd("foo", "bar")))
        #expect(shell("((foo))") == .success("foo"))
        #expect(shell("(a; b)") == .success(.seq("a", "b")))
        #expect(shell("(a && b) || c") == .success(.or(.and("a", "b"), "c")))
        #expect(shell("a && (b || c)") == .success(.and("a", .or("b", "c"))))
        #expect(shell("(a || b) && (c || d)") == .success(.and(.or("a", "b"), .or("c", "d"))))
    }

    @Test
    func testParserParensStartingWithNewlines() {
        #expect(shell("(\n  foo\n)") == .success("foo"))
        #expect(shell("( # comment\n  a;\n  b\n)") == .success(.seq("a", "b")))
        #expect(shell("a && (\n\n  b || c\n)") == .success(.and("a", .or("b", "c"))))
        #expect(shell("(\n)") == .failure("Line 2 Column 1: Expected at least one word. Got: )"))
    }

    @Test
    func testParserNewlineSeparatesCommands() {
        #expect(shell("foo\nbar") == .success(.seq("foo", "bar")))
        #expect(shell("foo bar;\nbaz") == .success(.seq(.cmd("foo", "bar"), "baz")))
        #expect(shell("a && b\n\n(c\nd) # comment\ne") == .success(.seq([.and("a", "b"), .seq("c", "d"), "e"])))
        #expect(shell("a\n&& b") == .failure("Line 1 Column 2: Please escape newline with backslash character."))
    }

    @Test
    func testParserTrailingOperator() {
        #expect(shell("foo;") == .success(.cmd("foo")))
        #expect(shell("foo\n\n") == .success(.cmd("foo")))
        #expect(shell("foo\n\n;\n") == .success(.cmd("foo")))

        #expect(shell("foo &&") == .failure("Line 1 Column 7: Expected at least one word. Got: End of input"))
        #expect(shell("foo ||") == .failure("Line 1 Column 7: Expected at least one word. Got: End of input"))
        #expect(shell("foo |") == .failure("Line 1 Column 6: Expected at least one word. Got: End of input"))
    }

    @Test
    func testParserFailLeadingOperator() {
        #expect(shell("&& foo") == .failure("Line 1 Column 1: Expected at least one word. Got: &&"))
        #expect(shell("|| foo") == .failure("Line 1 Column 1: Expected at least one word. Got: ||"))
        #expect(shell("| foo") == .failure("Line 1 Column 1: Expected at least one word. Got: |"))
        #expect(shell(";") == .failure("Line 1 Column 1: Expected at least one word. Got: ;"))
    }

    @Test
    func testParserFailParens() {
        #expect(shell("()") == .failure("Line 1 Column 2: Expected at least one word. Got: )"))
        #expect(shell("(foo") == .failure("Line 1 Column 5: Expected ')'. Got: 'End of input'"))
        #expect(shell("foo)") == .failure("Line 1 Column 4: Unexpected token ')'"))
        // Per the grammar, a parenthesized group is a Pipe-level atom and cannot itself be piped.
        #expect(shell("(foo) | bar") == .failure("Line 1 Column 7: Unexpected token '|'"))
    }

    @Test
    func testBuildDescription() {
        func render(_ shell: Shell<[String]>) -> String { shell.buildDescription { $0.joined(separator: " ") } }

        #expect(render(.or(.and("a", "b"), "c")) == "a && b || c")
        #expect(render(.seq(.or("a", "b"), .and("c", "d"))) == "a || b; c && d")
        #expect(render(.and(.pipe("a", "b"), "c")) == "a | b && c")

        #expect(render(.and(.or("a", "b"), "c")) == "(a || b) && c")
        #expect(render(.and("a", .or("b", "c"))) == "a && (b || c)")
        #expect(render(.pipe(.seq("a", "b"), "c")) == "(a; b) | c")
        #expect(render(.or(.seq("a", "b"), "c")) == "(a; b) || c")
        #expect(render(.and(.or("a", "b"), .or("c", "d"))) == "(a || b) && (c || d)")

        #expect(render("foo") == "foo")
        #expect(render(.and(["a", "b", "c"])) == "a && b && c")
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
