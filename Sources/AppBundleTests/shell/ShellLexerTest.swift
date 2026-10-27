@testable import AppBundle
import Common
import Testing

@Suite
struct ShellLexerTest {
    static let lexRows: [(label: String, input: String, tokens: [LexerToken])] = [
        ("words", "echo  foo", [.word(l: 1, c: 1, "echo"), .word(l: 1, c: 7, "foo"), .end(l: 1, c: 10)]),
        ("empty input", "", [.end(l: 1, c: 1)]),
        ("tabs are whitespace", "\techo\tfoo", [.word(l: 1, c: 2, "echo"), .word(l: 1, c: 7, "foo"), .end(l: 1, c: 10)]),
        ("a comment runs to the end of the line", "echo # hi\nfoo", [.word(l: 1, c: 1, "echo"), .newline(l: 1, c: 10), .word(l: 2, c: 1, "foo"), .end(l: 2, c: 4)]),
        ("a comment needs no space before it", "echo#nospace", [.word(l: 1, c: 1, "echo"), .end(l: 1, c: 13)]),
        ("single quotes keep spaces and double quotes", "echo 'a \"b'", [.word(l: 1, c: 1, "echo"), .word(l: 1, c: 6, "a \"b"), .end(l: 1, c: 12)]),
        ("double quotes keep spaces and single quotes", "echo \"it's here\"", [.word(l: 1, c: 1, "echo"), .word(l: 1, c: 6, "it's here"), .end(l: 1, c: 17)]),
        ("a quoted word may be empty", "echo ''", [.word(l: 1, c: 1, "echo"), .word(l: 1, c: 6, ""), .end(l: 1, c: 8)]),
        ("a quoted newline is part of the word", "echo 'foo\nbar'", [.word(l: 1, c: 1, "echo"), .word(l: 1, c: 6, "foo\nbar"), .end(l: 2, c: 5)]),
        ("operators need no spaces", "a|b||c&&d;e", [
            .word(l: 1, c: 1, "a"), .pipe(l: 1, c: 2), .word(l: 1, c: 3, "b"), .or(l: 1, c: 4), .word(l: 1, c: 6, "c"),
            .and(l: 1, c: 7), .word(l: 1, c: 9, "d"), .semicolon(l: 1, c: 10), .word(l: 1, c: 11, "e"), .end(l: 1, c: 12),
        ]),
        ("parens need no spaces", "(a)", [.lParen(l: 1, c: 1), .word(l: 1, c: 2, "a"), .rParen(l: 1, c: 3), .end(l: 1, c: 4)]),
        ("&& may follow a closing quote", "'a'&&b", [.word(l: 1, c: 1, "a"), .and(l: 1, c: 4), .word(l: 1, c: 6, "b"), .end(l: 1, c: 7)]),
        ("~= is a word, although ~ is reserved", "a ~= b", [.word(l: 1, c: 1, "a"), .word(l: 1, c: 3, "~="), .word(l: 1, c: 6, "b"), .end(l: 1, c: 7)]),
        ("newlines are tokens", "a\n\nb\n", [
            .word(l: 1, c: 1, "a"), .newline(l: 1, c: 2), .newline(l: 2, c: 1), .word(l: 3, c: 1, "b"), .newline(l: 3, c: 2), .end(l: 4, c: 1),
        ]),
        ("a backslash escapes the newline", "echo \\\nfoo", [.word(l: 1, c: 1, "echo"), .word(l: 2, c: 1, "foo"), .end(l: 2, c: 4)]),
        ("whitespace and a comment may follow the backslash", "echo \\ # hi\nfoo", [.word(l: 1, c: 1, "echo"), .word(l: 2, c: 1, "foo"), .end(l: 2, c: 4)]),
        ("an escaped newline may come before an operator", "echo \\\n&& foo", [.word(l: 1, c: 1, "echo"), .and(l: 2, c: 1), .word(l: 2, c: 4, "foo"), .end(l: 2, c: 7)]),
        // todo: the last word is dropped if it ends in a Unicode Prepend character (U+0600 here): the character joins the
        // synthetic trailing space into one Character, so the word never ends
        ("a last word that ends in a Prepend character", "echo \u{0600}", [.word(l: 1, c: 1, "echo"), .end(l: 1, c: 6)]),
    ]

    // `await`: the rows hold AppBundle types, which are MainActor-isolated, and the arguments are evaluated off the main actor
    @Test(arguments: await lexRows)
    func lexes(label: String, input: String, tokens: [LexerToken]) {
        expectEqual(lex(input), .success(tokens), Comment(rawValue: label))
    }

    @Test(arguments: [
        ("a newline before an operator must be escaped", "echo foo\n  || bar", "Line 1 Column 9: Please escape newline with backslash character."),
        ("an unclosed quote", "echo 'foo", "Line 1 Column 10: Last quote ' isn't closed."),
        ("a quote inside a bare word", "echo foo'bar'", "Line 1 Column 9: Please put a space in front of the quote character."),
        ("a quote right after a closing quote", "echo 'a'\"b\"", "Line 1 Column 9: Please put a space in front of the quote character."),
        ("a word right after a closing quote", "echo 'foo'bar", "Line 1 Column 11: Please put a space after closing quote."),
        ("a reserved character in a bare word", "echo $foo", "Line 1 Column 6: Bare word '$foo' contains reserved character: $. Please quote the bare word if you want to use the character."),
        ("~ is reserved", "echo ~", "Line 1 Column 6: Bare word '~' contains reserved character: ~. Please quote the bare word if you want to use the character."),
        ("a backslash followed by a word", "echo \\a", "Line 1 Column 7: backslash can be followed only by whitespaces, newlines and comments, but it is followed by 'a'."),
        ("a backslash right before a comment", "echo \\#foo", "Line 1 Column 6: Please put a space between backslash and a comment start"),
    ] as [(String, String, String)])
    func lexFails(label: String, input: String, message: String) {
        expectEqual(lex(input), .failure(.invalid(message)), Comment(rawValue: label))
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
