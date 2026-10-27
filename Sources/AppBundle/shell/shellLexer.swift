import Common

extension String {
    func shellLexerTokens() throws(CmdParseError) -> [LexerToken] {
        var lexer = ShellLexer(chars: locateChars(self + " ")) // synthetic trailing space to flush the last word
        return try lexer.lex()
    }
}

private let reservedChars: Set<Unicode.Scalar> = ["(", ")", "$", "~", "&", "?", "*", "!", "\\", "|", "<", ">", "`", "'", "\"", "#", "\n"]

/// Besides whitespace and "&&", these characters end a bare word
private let wordTerminators: Set<Unicode.Scalar> = ["|", "\\", "#", ";", "(", ")", "'", "\""]

/// Walks unicode scalars, not Characters: a Character can join a delimiter with its neighbor (a Unicode Prepend character,
/// e.g. U+0600, joins the space or quote after it)
private struct ShellLexer {
    let chars: [LocatedChar]
    var index = 0
    var tokens: [LexerToken] = []

    var char: Unicode.Scalar? { chars.getOrNil(atIndex: index)?.value }
    var next: Unicode.Scalar? { chars.getOrNil(atIndex: index + 1)?.value }
    var location: Location { chars[index].location }

    mutating func lex() throws(CmdParseError) -> [LexerToken] {
        while let char {
            switch char {
                case "\n": emit(.newline)
                case "&" where next == "&": emit(.and, length: 2)
                case "|" where next == "|": emit(.or, length: 2)
                case "|": emit(.pipe)
                case ";": emit(.semicolon)
                case "(": emit(.lParen)
                case ")": emit(.rParen)
                case "\\" where next == "#": throw "\(location): Please put a space between backslash and a comment start"
                case "\\": try skipLineContinuation()
                case "#": skipComment()
                case "'", "\"": try lexQuotedWord()
                case _ where char.properties.isWhitespace: index += 1
                default: try lexBareWord()
            }
        }
        tokens.append(.init(chars.last.orDie().location, .end))
        for (token, next) in zip(tokens, tokens.dropFirst()) where token.payload == .newline && [.and, .or, .pipe].contains(next.payload) {
            throw "\(token.location): Please escape newline with backslash character."
        }
        return tokens
    }

    private mutating func emit(_ payload: LexerToken.Payload, length: Int = 1) {
        tokens.append(.init(location, payload))
        index += length
    }

    private mutating func skipComment() {
        while let char, char != "\n" { index += 1 }
    }

    /// A backslash escapes the next newline. Only whitespace and a comment may come in between
    private mutating func skipLineContinuation() throws(CmdParseError) {
        index += 1
        while let char, char != "\n" {
            if char == "#" {
                skipComment()
            } else if char.properties.isWhitespace {
                index += 1
            } else {
                throw "\(location): backslash can be followed only by whitespaces, newlines and comments, but it is followed by \(char.description.singleQuoted)."
            }
        }
        index += 1
    }

    private mutating func lexQuotedWord() throws(CmdParseError) {
        let quote = chars[index]
        index += 1
        var word = ""
        while let char, char != quote.value {
            word.unicodeScalars.append(char)
            index += 1
        }
        if char == nil {
            throw "\(chars.last.orDie().location): Last quote \(quote.value) isn't closed."
        }
        index += 1
        tokens.append(.init(quote.location, .word(word)))
        switch char {
            case "'", "\"": throw "\(location): Please put a space in front of the quote character."
            case let char? where !char.properties.isWhitespace && !wordTerminators.contains(char) && !(char == "&" && next == "&"):
                throw "\(location): Please put a space after closing quote."
            default: break
        }
    }

    private mutating func lexBareWord() throws(CmdParseError) {
        let start = location
        var word = ""
        while let char, !char.properties.isWhitespace, !wordTerminators.contains(char), !(char == "&" && next == "&") {
            word.unicodeScalars.append(char)
            index += 1
        }
        if char == "'" || char == "\"" {
            throw "\(location): Please put a space in front of the quote character."
        }
        if word != "~=", let reservedChar = word.unicodeScalars.first(where: { reservedChars.contains($0) }) {
            throw "\(start): Bare word '\(word)' contains reserved character: \(reservedChar). Please quote the bare word if you want to use the character."
        }
        tokens.append(.init(start, .word(word)))
    }
}

private struct LocatedChar {
    let value: Unicode.Scalar
    let location: Location
}

private func locateChars(_ str: String) -> [LocatedChar] {
    var result = [LocatedChar]()
    var location = Location(line: 1, column: 1)
    for char in str.unicodeScalars {
        result.append(LocatedChar(value: char, location: location))
        location.column += 1
        if char == "\n" {
            location.line += 1
            location.column = 1
        }
    }
    return result
}

struct LexerToken: Equatable {
    let location: Location
    let payload: Payload

    init(_ location: Location, _ payload: Payload) {
        self.location = location
        self.payload = payload
    }

    enum Payload: Equatable, CustomStringConvertible {
        case end

        case word(String)

        case and // &&
        case or // ||
        case pipe // |

        case lParen // (
        case rParen // )

        case semicolon // ;
        case newline // \n

        var description: String {
            switch self {
                case .end: "End of input"
                case .and: "&&"
                case .lParen: "("
                case .newline: "\n"
                case .or: "||"
                case .pipe: "|"
                case .rParen: ")"
                case .semicolon: ";"
                case .word(let word): word
            }
        }
    }
}

struct Location: CustomStringConvertible, Equatable {
    var line: Int
    var column: Int

    var description: String { "Line \(line) Column \(column)" }
}
