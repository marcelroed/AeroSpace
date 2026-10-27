import Common

// Root = "\n"* Seq? EndOfInput
//
// EndOfInput = /$/
//
// Seq = Or ((";" | "\n")+ Or?)*
//
// Or = And ("||" And)*
//
// And = Pipe ("&&" Pipe)*
//
// Pipe
//   = "(" "\n"* Seq ")"
//   | Cmd ("|" Cmd)*
//
// Cmd = Word+

extension String {
    func lexAndParseShell() -> ResOrStr<Shell<[String]>> {
        self.shellLexerTokens().flatMap { tokens in
            Result { () throws(String) in
                var parser = ShellParser(tokens: tokens)
                parser.skipNewlines() // Skip leading empty lines and comment lines
                if parser.peek.payload == .end { return .empty }
                let result = try parser.parse(.seq)
                if parser.peek.payload != .end {
                    throw "\(parser.peek.location): Unexpected token \(parser.peek.payload.description.singleQuoted)"
                }
                return result
            }
        }
    }
}

/// Recursive descent: `parse(op)` parses the grammar rule of `op`, whose operands are the rule of the next higher precedence.
/// A chain nests to the left: `a && b && c` is `(a && b) && c`
private struct ShellParser {
    let tokens: [LexerToken]
    var index = 0

    var peek: LexerToken { tokens[index] }

    mutating func parse(_ op: ShellOp) throws(String) -> Shell<[String]> {
        switch op {
            case .seq: try parseSeq()
            case .or: try parseChain(.or, separator: .or)
            case .and: try parseChain(.and, separator: .and)
            case .pipe: peek.payload == .lParen ? try parseGroup() : try parseChain(.pipe, separator: .pipe)
        }
    }

    /// `Operand (separator Operand)*`
    private mutating func parseChain(_ op: ShellOp, separator: LexerToken.Payload) throws(String) -> Shell<[String]> {
        var result = try parseOperand(of: op)
        while peek.payload == separator {
            index += 1
            result = .op(op, result, try parseOperand(of: op))
        }
        return result
    }

    private mutating func parseOperand(of op: ShellOp) throws(String) -> Shell<[String]> {
        if let next = ShellOp(rawValue: op.rawValue + 1) { try parse(next) } else { try parseCmd() }
    }

    /// Like `parseChain(.seq, …)`, but a separator is one or more of ';' and newline, and the trailing one is optional
    private mutating func parseSeq() throws(String) -> Shell<[String]> {
        var result = try parse(.or)
        while peek.payload.isSeqSeparator {
            while peek.payload.isSeqSeparator { index += 1 }
            // FIRST(Or) = FIRST(And) = FIRST(Pipe) = { "(" } ∪ FIRST(Cmd) = { "(", Word }
            if peek.payload.isWord || peek.payload == .lParen {
                result = .op(.seq, result, try parse(.or))
            }
        }
        return result
    }

    mutating func skipNewlines() {
        while peek.payload == .newline { index += 1 }
    }

    private mutating func parseGroup() throws(String) -> Shell<[String]> {
        index += 1
        skipNewlines() // Like at the top level
        let result = try parse(.seq)
        if peek.payload != .rParen {
            throw "\(peek.location): Expected ')'. Got: \(peek.payload.description.singleQuoted)"
        }
        index += 1
        return result
    }

    private mutating func parseCmd() throws(String) -> Shell<[String]> {
        var words = [String]()
        while case .word(let word) = peek.payload {
            words.append(word)
            index += 1
        }
        if words.isEmpty {
            throw "\(peek.location): Expected at least one word. Got: \(peek.payload)"
        }
        return .cmd(words)
    }
}

extension LexerToken.Payload {
    fileprivate var isSeqSeparator: Bool { self == .semicolon || self == .newline }

    fileprivate var isWord: Bool {
        if case .word = self { true } else { false }
    }
}
