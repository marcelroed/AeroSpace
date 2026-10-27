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

private let binaryOpTokens: [ShellOp: LexerToken.Payload] = [.or: .or, .and: .and, .pipe: .pipe]

/// Recursive descent: `parse(op)` parses the grammar rule of `op`, whose operands are the rule of the next higher precedence
private struct ShellParser {
    let tokens: [LexerToken]
    var index = 0

    var peek: LexerToken { tokens[index] }

    mutating func parse(_ op: ShellOp) throws(String) -> Shell<[String]> {
        switch op {
            case .seq: return try parseSeq()
            case .pipe where peek.payload == .lParen: return try parseGroup()
            case .or, .and, .pipe: break
        }
        var elems = [try parseOperand(of: op)]
        while peek.payload == binaryOpTokens[op] {
            index += 1
            elems.append(try parseOperand(of: op))
        }
        return .compound(op, elems)
    }

    private mutating func parseOperand(of op: ShellOp) throws(String) -> Shell<[String]> {
        if let next = ShellOp(rawValue: op.rawValue + 1) { try parse(next) } else { try parseCmd() }
    }

    private mutating func parseSeq() throws(String) -> Shell<[String]> {
        var elems = [try parse(.or)]
        while peek.payload.isSeqSeparator {
            while peek.payload.isSeqSeparator { index += 1 }
            // FIRST(Or) = FIRST(And) = FIRST(Pipe) = { "(" } ∪ FIRST(Cmd) = { "(", Word }
            if peek.payload.isWord || peek.payload == .lParen {
                elems.append(try parse(.or))
            }
        }
        return .compound(.seq, elems)
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
