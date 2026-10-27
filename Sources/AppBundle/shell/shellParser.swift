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
    func lexAndParseShell() throws(CmdParseError) -> Shell<[String]> {
        var parser = ShellParser(tokens: try shellLexerTokens())
        parser.skipNewlines() // Skip leading empty lines and comment lines
        if parser.peek.payload == .end { return .empty }
        let result = try parser.parse(.seq)
        if parser.peek.payload != .end {
            throw "\(parser.peek.location): Unexpected token \(parser.peek.payload.description.singleQuoted)"
        }
        return result
    }
}

/// The parser recurses once per group, and everything that walks a `Shell` (run, map, description, deinit) recurses once
/// per operator, since a chain nests to the left. The input comes from the CLI too (`eval`), so both are bounded: a
/// stack overflow would crash the server. A config array of commands counts as one expression (decodeShellOfCommands)
let maxShellGroupNesting = 100
let maxShellOperators = 1000

/// Recursive descent: `parse(op)` parses the grammar rule of `op`, whose operands are the rule of the next higher precedence.
/// A chain nests to the left: `a && b && c` is `(a && b) && c`
private struct ShellParser {
    let tokens: [LexerToken]
    var index = 0
    private var groupNesting = 0
    private var operators = 0

    init(tokens: [LexerToken]) { self.tokens = tokens }

    var peek: LexerToken { tokens[index] }

    mutating func parse(_ op: ShellOp) throws(CmdParseError) -> Shell<[String]> {
        switch op {
            case .seq: try parseSeq()
            case .or: try parseChain(.or, separator: .or)
            case .and: try parseChain(.and, separator: .and)
            case .pipe: peek.payload == .lParen ? try parseGroup() : try parseChain(.pipe, separator: .pipe)
        }
    }

    /// `Operand (separator Operand)*`
    private mutating func parseChain(_ op: ShellOp, separator: LexerToken.Payload) throws(CmdParseError) -> Shell<[String]> {
        var result = try parseOperand(of: op)
        while peek.payload == separator {
            try countOperator()
            index += 1
            result = .op(op, result, try parseOperand(of: op))
        }
        return result
    }

    private mutating func parseOperand(of op: ShellOp) throws(CmdParseError) -> Shell<[String]> {
        if let next = ShellOp(rawValue: op.rawValue + 1) { try parse(next) } else { try parseCmd() }
    }

    /// Like `parseChain(.seq, …)`, but a separator is one or more of ';' and newline, and the trailing one is optional
    private mutating func parseSeq() throws(CmdParseError) -> Shell<[String]> {
        var result = try parse(.or)
        while peek.payload.isSeqSeparator {
            while peek.payload.isSeqSeparator { index += 1 }
            // FIRST(Or) = FIRST(And) = FIRST(Pipe) = { "(" } ∪ FIRST(Cmd) = { "(", Word }
            if peek.payload.isWord || peek.payload == .lParen {
                try countOperator()
                result = .op(.seq, result, try parse(.or))
            }
        }
        return result
    }

    mutating func skipNewlines() {
        while peek.payload == .newline { index += 1 }
    }

    private mutating func countOperator() throws(CmdParseError) {
        operators += 1
        if operators > maxShellOperators { throw "\(peek.location): More than \(maxShellOperators) operators in one expression" }
    }

    private mutating func parseGroup() throws(CmdParseError) -> Shell<[String]> {
        if groupNesting == maxShellGroupNesting {
            throw "\(peek.location): Parentheses are nested deeper than \(maxShellGroupNesting) levels"
        }
        groupNesting += 1
        defer { groupNesting -= 1 }
        index += 1
        skipNewlines() // Like at the top level
        let result = try parse(.seq)
        if peek.payload != .rParen {
            throw "\(peek.location): Expected ')'. Got: \(peek.payload.description.singleQuoted)"
        }
        index += 1
        return result
    }

    private mutating func parseCmd() throws(CmdParseError) -> Shell<[String]> {
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
