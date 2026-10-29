import Common

private let reservedChars: Set<Unicode.Scalar> = ["(", ")", "$", "~", "&", "?", "*", "!", "\\", "|", "<", ">", "`", "'", "\"", "#", "\n"]

/// Besides whitespace and "&&", these characters end a bare word
private let wordTerminators: Set<Unicode.Scalar> = ["|", "\\", "#", ";", "(", ")", "'", "\""]

/// Lexes one token per call, so the parser's limits also stop the lexing of a long input. It walks unicode scalars, not
/// Characters: a Character can join a delimiter with its neighbor (a Unicode Prepend character, e.g. U+0600, joins the
/// space or quote after it)
struct ShellLexer {
    private let input: String.UnicodeScalarView
    private var index: String.UnicodeScalarView.Index
    private var location = Location(line: 1, column: 1)

    init(_ input: String) {
        self.input = input.unicodeScalars
        index = self.input.startIndex
    }

    private var char: Unicode.Scalar? { input[index...].first }
    private var next: Unicode.Scalar? { input[index...].dropFirst().first }

    mutating func nextToken() throws(CmdParseError) -> LexerToken {
        while let char {
            switch char {
                case "\n": return token(.newline)
                case "&" where next == "&": return token(.and, length: 2)
                case "|" where next == "|": return token(.or, length: 2)
                case "|": return token(.pipe)
                case ";": return token(.semicolon)
                case "(": return token(.lParen)
                case ")": return token(.rParen)
                case "\\" where next == "#": throw "\(location): Please put a space between backslash and a comment start"
                case "\\": try skipLineContinuation()
                case "#": skipComment()
                case "'", "\"": return try lexQuotedWord()
                case _ where char.properties.isWhitespace: advance()
                default: return try lexBareWord()
            }
        }
        return LexerToken(location, .end)
    }

    private mutating func token(_ payload: LexerToken.Payload, length: Int = 1) -> LexerToken {
        let token = LexerToken(location, payload)
        for _ in 0 ..< length { advance() }
        return token
    }

    private mutating func advance() {
        if input[index] == "\n" {
            location = Location(line: location.line + 1, column: 1)
        } else {
            location.column += 1
        }
        input.formIndex(after: &index)
    }

    private mutating func skipComment() {
        while let char, char != "\n" { advance() }
    }

    /// A backslash escapes the next newline. Only whitespace and a comment may come in between
    private mutating func skipLineContinuation() throws(CmdParseError) {
        advance()
        while let char, char != "\n" {
            if char == "#" {
                skipComment()
            } else if char.properties.isWhitespace {
                advance()
            } else {
                throw "\(location): backslash can be followed only by whitespaces, newlines and comments, but it is followed by \(char.description.singleQuoted)."
            }
        }
        if char != nil { advance() }
    }

    private mutating func lexQuotedWord() throws(CmdParseError) -> LexerToken {
        let start = location
        let quote = input[index]
        advance()
        let wordStart = index
        while let char, char != quote { advance() }
        if char == nil {
            throw "\(location): Last quote \(quote) isn't closed."
        }
        let word = String(input[wordStart ..< index])
        advance()
        switch char {
            case "'", "\"": throw "\(location): Please put a space in front of the quote character."
            case let char? where !char.properties.isWhitespace && !wordTerminators.contains(char) && !(char == "&" && next == "&"):
                throw "\(location): Please put a space after closing quote."
            default: return LexerToken(start, .word(word))
        }
    }

    private mutating func lexBareWord() throws(CmdParseError) -> LexerToken {
        let start = location
        let wordStart = index
        while let char, !char.properties.isWhitespace, !wordTerminators.contains(char), !(char == "&" && next == "&") {
            advance()
        }
        if char == "'" || char == "\"" {
            throw "\(location): Please put a space in front of the quote character."
        }
        let word = String(input[wordStart ..< index])
        if word != "~=", let reservedChar = word.unicodeScalars.first(where: { reservedChars.contains($0) }) {
            throw "\(start): Bare word '\(word)' contains reserved character: \(reservedChar). Please quote the bare word if you want to use the character."
        }
        return LexerToken(start, .word(word))
    }
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
