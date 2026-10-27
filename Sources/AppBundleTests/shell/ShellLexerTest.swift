@testable import AppBundle
import Common
import Testing

@Suite
struct ShellLexerTest {
    @Test
    func testLexer() {
        expectEqual(lex("echo foo"), .success([.word(l: 1, c: 1, "echo"), .word(l: 1, c: 6, "foo"), .end(l: 1, c: 9)]))
        expectEqual(lex("echo  foo"), .success([.word(l: 1, c: 1, "echo"), .word(l: 1, c: 7, "foo"), .end(l: 1, c: 10)]))
        expectEqual(lex("echo 'foo' &&"), .success([.word(l: 1, c: 1, "echo"), .word(l: 1, c: 6, "foo"), .and(l: 1, c: 12), .end(l: 1, c: 14)]))
        expectEqual(lex("echo 'foo' \\ \n&&"), .success([.word(l: 1, c: 1, "echo"), .word(l: 1, c: 6, "foo"), .and(l: 2, c: 1), .end(l: 2, c: 3)]))
        expectEqual(lex("echo 'foo'\n &&"), .failure("Line 1 Column 11: Please escape newline with backslash character."))
        expectEqual(lex("echo 'foo' \n &&"), .failure("Line 1 Column 12: Please escape newline with backslash character."))

        expectEqual(lex("echo ''"), .success([.word(l: 1, c: 1, "echo"), .word(l: 1, c: 6, ""), .end(l: 1, c: 8)]))
    }

    @Test
    func testLexerEmpty() {
        expectEqual(lex(""), .success([.end(l: 1, c: 1)]))
        expectEqual(lex("   "), .success([.end(l: 1, c: 4)]))
        expectEqual(lex("\t"), .success([.end(l: 1, c: 2)]))
    }

    @Test
    func testLexerLeadingWhitespace() {
        expectEqual(lex("  echo"), .success([.word(l: 1, c: 3, "echo"), .end(l: 1, c: 7)]))
        expectEqual(lex("\techo\tfoo"), .success([.word(l: 1, c: 2, "echo"), .word(l: 1, c: 7, "foo"), .end(l: 1, c: 10)]))
    }

    @Test
    func testLexerComments() {
        expectEqual(lex("# hello"), .success([.end(l: 1, c: 8)]))
        expectEqual(lex("echo # comment"), .success([.word(l: 1, c: 1, "echo"), .end(l: 1, c: 15)]))
        expectEqual(lex("echo#nospace"), .success([.word(l: 1, c: 1, "echo"), .end(l: 1, c: 13)]))
        expectEqual(lex("echo # hi\nfoo"), .success([.word(l: 1, c: 1, "echo"), .newline(l: 1, c: 10), .word(l: 2, c: 1, "foo"), .end(l: 2, c: 4)]))
    }

    @Test
    func testLexerSingleQuotes() {
        expectEqual(lex("echo 'hello world'"), .success([.word(l: 1, c: 1, "echo"), .word(l: 1, c: 6, "hello world"), .end(l: 1, c: 19)]))
        expectEqual(lex("'foo'"), .success([.word(l: 1, c: 1, "foo"), .end(l: 1, c: 6)]))
        expectEqual(lex("echo 'a\"b'"), .success([.word(l: 1, c: 1, "echo"), .word(l: 1, c: 6, "a\"b"), .end(l: 1, c: 11)]))
    }

    @Test
    func testLexerDoubleQuotes() {
        expectEqual(lex("echo \"hello world\""), .success([.word(l: 1, c: 1, "echo"), .word(l: 1, c: 6, "hello world"), .end(l: 1, c: 19)]))
        expectEqual(lex("\"foo\""), .success([.word(l: 1, c: 1, "foo"), .end(l: 1, c: 6)]))
        expectEqual(lex("echo \"it's\""), .success([.word(l: 1, c: 1, "echo"), .word(l: 1, c: 6, "it's"), .end(l: 1, c: 12)]))
    }

    @Test
    func testLexerQuotedNewline() {
        expectEqual(lex("echo 'foo\nbar'"), .success([.word(l: 1, c: 1, "echo"), .word(l: 1, c: 6, "foo\nbar"), .end(l: 2, c: 5)]))
    }

    @Test
    func testLexerPipeAndOr() {
        expectEqual(lex("echo foo | bar"), .success([.word(l: 1, c: 1, "echo"), .word(l: 1, c: 6, "foo"), .pipe(l: 1, c: 10), .word(l: 1, c: 12, "bar"), .end(l: 1, c: 15)]))
        expectEqual(lex("echo foo || bar"), .success([.word(l: 1, c: 1, "echo"), .word(l: 1, c: 6, "foo"), .or(l: 1, c: 10), .word(l: 1, c: 13, "bar"), .end(l: 1, c: 16)]))
        expectEqual(lex("a|b"), .success([.word(l: 1, c: 1, "a"), .pipe(l: 1, c: 2), .word(l: 1, c: 3, "b"), .end(l: 1, c: 4)]))
        expectEqual(lex("a||b"), .success([.word(l: 1, c: 1, "a"), .or(l: 1, c: 2), .word(l: 1, c: 4, "b"), .end(l: 1, c: 5)]))
        expectEqual(lex("a&&b"), .success([.word(l: 1, c: 1, "a"), .and(l: 1, c: 2), .word(l: 1, c: 4, "b"), .end(l: 1, c: 5)]))
    }

    @Test
    func testLexerSemicolon() {
        expectEqual(lex("echo a;b"), .success([.word(l: 1, c: 1, "echo"), .word(l: 1, c: 6, "a"), .semicolon(l: 1, c: 7), .word(l: 1, c: 8, "b"), .end(l: 1, c: 9)]))
        expectEqual(lex("echo foo; echo bar"), .success([.word(l: 1, c: 1, "echo"), .word(l: 1, c: 6, "foo"), .semicolon(l: 1, c: 9), .word(l: 1, c: 11, "echo"), .word(l: 1, c: 16, "bar"), .end(l: 1, c: 19)]))
    }

    @Test
    func testLexerParens() {
        expectEqual(lex("(echo)"), .success([.lParen(l: 1, c: 1), .word(l: 1, c: 2, "echo"), .rParen(l: 1, c: 6), .end(l: 1, c: 7)]))
        expectEqual(lex("( echo foo )"), .success([.lParen(l: 1, c: 1), .word(l: 1, c: 3, "echo"), .word(l: 1, c: 8, "foo"), .rParen(l: 1, c: 12), .end(l: 1, c: 13)]))
    }

    @Test
    func testLexerBackslashLineContinuation() {
        expectEqual(lex("echo \\\n foo"), .success([.word(l: 1, c: 1, "echo"), .word(l: 2, c: 2, "foo"), .end(l: 2, c: 5)]))
        expectEqual(lex("echo \\\nfoo"), .success([.word(l: 1, c: 1, "echo"), .word(l: 2, c: 1, "foo"), .end(l: 2, c: 4)]))
        expectEqual(lex("echo \\ \nfoo"), .success([.word(l: 1, c: 1, "echo"), .word(l: 2, c: 1, "foo"), .end(l: 2, c: 4)]))
    }

    @Test
    func testLexerMultipleNewlines() {
        expectEqual(lex("\n\n\n"), .success([.newline(l: 1, c: 1), .newline(l: 2, c: 1), .newline(l: 3, c: 1), .end(l: 4, c: 1)]))
        expectEqual(lex("echo foo\necho bar"), .success([.word(l: 1, c: 1, "echo"), .word(l: 1, c: 6, "foo"), .newline(l: 1, c: 9), .word(l: 2, c: 1, "echo"), .word(l: 2, c: 6, "bar"), .end(l: 2, c: 9)]))
        expectEqual(lex("echo foo\n"), .success([.word(l: 1, c: 1, "echo"), .word(l: 1, c: 6, "foo"), .newline(l: 1, c: 9), .end(l: 2, c: 1)]))
    }

    @Test
    func testLexerFailUnclosedQuote() {
        expectEqual(lex("echo 'foo"), .failure("Line 1 Column 10: Last quote ' isn't closed."))
        expectEqual(lex("echo \"foo"), .failure("Line 1 Column 10: Last quote \" isn't closed."))
    }

    @Test
    func testLexerFailQuoteInMiddleOfWord() {
        expectEqual(lex("echo foo'bar'"), .failure("Line 1 Column 9: Please put a space in front of the quote character."))
    }

    @Test
    func testLexerFailMissingSpaceAfterClosingQuote() {
        expectEqual(lex("echo 'foo'bar"), .failure("Line 1 Column 11: Please put a space after closing quote."))
    }

    @Test
    func testLexerFailReservedChar() {
        expectEqual(lex("echo $foo"), .failure("Line 1 Column 6: Bare word '$foo' contains reserved character: $. Please quote the bare word if you want to use the character."))
        expectEqual(lex("echo *"), .failure("Line 1 Column 6: Bare word '*' contains reserved character: *. Please quote the bare word if you want to use the character."))
        expectEqual(lex("echo ~"), .failure("Line 1 Column 6: Bare word '~' contains reserved character: ~. Please quote the bare word if you want to use the character."))
    }

    @Test
    func testLexerFailBackslashFollowedByNonWhitespace() {
        expectEqual(lex("echo \\a"), .failure("Line 1 Column 7: backslash can be followed only by whitespaces, newlines and comments, but it is followed by 'a'."))
    }

    @Test
    func testLexerFailBackslashFollowedByComment() {
        expectEqual(lex("echo \\#foo"), .failure("Line 1 Column 6: Please put a space between backslash and a comment start"))
    }
}

extension LexerToken {
    static func word(l: Int, c: Int, _ str: String) -> Self { .init(Location(line: l, column: c), .word(str)) }
    static func and(l: Int, c: Int) -> Self { .init(Location(line: l, column: c), .and) }
    static func or(l: Int, c: Int) -> Self { .init(Location(line: l, column: c), .or) }
    static func pipe(l: Int, c: Int) -> Self { .init(Location(line: l, column: c), .pipe) }
    static func lParen(l: Int, c: Int) -> Self { .init(Location(line: l, column: c), .lParen) }
    static func rParen(l: Int, c: Int) -> Self { .init(Location(line: l, column: c), .rParen) }
    static func semicolon(l: Int, c: Int) -> Self { .init(Location(line: l, column: c), .semicolon) }
    static func end(l: Int, c: Int) -> Self { .init(Location(line: l, column: c), .end) }
    static func newline(l: Int, c: Int) -> Self { .init(Location(line: l, column: c), .newline) }
}

private func lex(_ raw: String) -> Result<[LexerToken], CmdParseError> {
    Result { () throws(CmdParseError) in try raw.shellLexerTokens() }
}
