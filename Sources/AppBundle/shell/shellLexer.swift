import Common

extension String {
    func shellLexerTokens() -> ResOrStr<[LexerToken]> {
        Result { () throws(String) in try _shellLexerTokens(self) }
    }
}

private func _shellLexerTokens(_ str: String) throws(String) -> [LexerToken] {
    var result: [LexerToken] = []
    var word: String = ""
    var state: State = .skipWhitespaces

    var index = 0
    var wordLocation = Location(line: 1, column: 1)
    let array = locateChars(str + " ") // synthetic trailing space to flush the last word

    func flushWord(quoted: Bool = false) throws(String) {
        if !quoted, word != "~=", let reservedChar = word.first(where: { reservedChars.contains($0) }) {
            throw "\(wordLocation): Bare word '\(word)' contains reserved character: \(reservedChar). Please quote the bare word if you want to use the character."
        }
        if quoted || !word.isEmpty {
            result.append(.init(wordLocation, .word(word)))
            word = ""
        }
        state = .skipWhitespaces
    }

    while let char = array.getOrNil(atIndex: index) {
        index += 1
        switch (state, char.value) { // State machine
            case (.comment, "\n"): // End comment
                result.append(.init(char.location, .newline))
                state = .skipWhitespaces
            case (.comment, _): break // Skip comment

            case (.quotedWord(quoteChar: char.value), _): // Close quotes
                try flushWord(quoted: true)
                state = .rightAfterQuotedWord
            case (.quotedWord, _): // Yet another character of a quoted word
                word.append(char.value)

            case (.backslash, "#"): // Skip comments after backslash
                while let next = array.getOrNil(atIndex: index), next.value != "\n" { index += 1 }
            case (.backslash, "\n"): state = .skipWhitespaces
            case (.backslash, _) where char.value.isWhitespace: break
            case (.backslash, _): throw "\(char.location): backslash can be followed only by whitespaces, newlines and comments, but it is followed by \(char.value.description.singleQuoted)."

            // All the remaining states below: .skipWhitespaces, .bareWord, or .rightAfterQuotedWord

            case (_, "\n"):
                try flushWord()
                result.append(.init(char.location, .newline))
            case (.rightAfterQuotedWord, _) where char.value.isWhitespace:
                state = .skipWhitespaces

            case (_, "&") where array.getOrNil(atIndex: index)?.value == "&":
                try flushWord()
                result.append(.init(char.location, .and))
                index += 1
            case (_, "|") where array.getOrNil(atIndex: index)?.value == "|":
                try flushWord()
                result.append(.init(char.location, .or))
                index += 1
            case (_, "|"):
                try flushWord()
                result.append(.init(char.location, .pipe))
            case (_, "\\") where array.getOrNil(atIndex: index)?.value == "#":
                throw "\(char.location): Please put a space between backslash and a comment start"
            case (_, "\\"):
                try flushWord()
                state = .backslash
            case (_, "#"): // Start comment
                try flushWord()
                state = .comment
            case (_, ";"):
                try flushWord()
                result.append(.init(char.location, .semicolon))
            case (_, "("):
                try flushWord()
                result.append(.init(char.location, .lParen))
            case (_, ")"):
                try flushWord()
                result.append(.init(char.location, .rParen))

            case (.skipWhitespaces, _) where char.value.isQuote: // Open quotes
                state = .quotedWord(quoteChar: char.value)
                wordLocation = char.location
            case _ where char.value.isQuote:
                throw "\(char.location): Please put a space in front of the quote character."
            case (.rightAfterQuotedWord, _):
                throw "\(char.location): Please put a space after closing quote."

            case (.skipWhitespaces, _) where !char.value.isWhitespace: // Start bare word
                state = .bareWord
                wordLocation = char.location
                word.append(char.value)
            case (.skipWhitespaces, _): break // Skip whitespaces

            case (.bareWord, _) where char.value.isWhitespace: // End bare word
                try flushWord()
            case (.bareWord, _): // Yet another character of a bare word
                word.append(char.value)
        }
    }
    let endLocation = array.last.orDie().location
    switch state {
        case .comment, .skipWhitespaces, .rightAfterQuotedWord, .backslash, .bareWord: break
        case .quotedWord(let quoteChar):
            throw "\(endLocation): Last quote \(quoteChar) isn't closed."
    }
    result.append(.init(endLocation, .end))
    try checkNoNewlineBeforeBinaryOperator(result)
    return result
}

private func checkNoNewlineBeforeBinaryOperator(_ tokens: [LexerToken]) throws(String) {
    let binaryOperators: [LexerToken.Payload] = [.and, .or, .pipe]
    for (token, next) in zip(tokens, tokens.dropFirst()) where token.payload == .newline && binaryOperators.contains(next.payload) {
        throw "\(token.location): Please escape newline with backslash character."
    }
}

private struct LocatedChar {
    let value: Character
    let location: Location
}

private func locateChars(_ str: String) -> [LocatedChar] {
    var result = [LocatedChar]()
    var location = Location(line: 1, column: 1)
    for char in str {
        result.append(LocatedChar(value: char, location: location))
        location.column += 1
        if char == "\n" {
            location.line += 1
            location.column = 1
        }
    }
    return result
}

private let reservedChars: Set<Character> = ["(", ")", "$", "~", "&", "?", "*", "!", "\\", "|", "<", ">", "`", "'", "\"", "#", "\n"]

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

extension Character {
    fileprivate var isQuote: Bool { self == "'" || self == "\"" }
}

private enum State {
    case comment
    case quotedWord(quoteChar: Character)

    case backslash

    case bareWord
    case skipWhitespaces
    case rightAfterQuotedWord
}
