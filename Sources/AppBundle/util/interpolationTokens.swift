import Common

extension String {
    /// The tokens of a string with interpolation variables: `%{window-id}` in a format, `${HOME}` in an exec env variable.
    /// Linear: the state holds no text, the current literal or variable name grows in place
    nonisolated func rawInterpolationTokens(interpolationChar: Character) throws(CmdParseError) -> [InterToken<String>] {
        var state: InterpolationParserState = .stringLiteral
        var buffer = "" // The current literal, or the current variable name
        var result: [InterToken<String>] = []
        for char in self {
            switch (state, char) { // State machine
                case (.stringLiteral, interpolationChar):
                    state = .interpolationCharEncountered
                case (.stringLiteral, _):
                    buffer.append(char)
                case (.interpolationCharEncountered, "{"):
                    result.append(.literal(buffer))
                    buffer = ""
                    state = .interpolationVariable
                case (.interpolationCharEncountered, interpolationChar):
                    buffer.append(interpolationChar)
                case (.interpolationCharEncountered, _):
                    buffer.append(interpolationChar)
                    buffer.append(char)
                    state = .stringLiteral
                case (.interpolationVariable, "}"):
                    result.append(.interVar(buffer))
                    buffer = ""
                    state = .stringLiteral
                case (.interpolationVariable, "{"):
                    throw "Can't parse '\(buffer + "{")' inside interpolation (Open curly brace is invalid character)"
                case (.interpolationVariable, interpolationChar):
                    throw "Can't parse '\(buffer + String(interpolationChar))' inside interpolation ('\(interpolationChar)' is disallowed character)"
                case (.interpolationVariable, _):
                    buffer.append(char)
            }
        }
        switch state {
            case .stringLiteral: result.append(.literal(buffer))
            case .interpolationCharEncountered: result.append(.literal(buffer + String(interpolationChar)))
            case .interpolationVariable: throw "Unbalanced curly braces"
        }
        return result.filter { $0 != .literal("") }
    }
}

nonisolated enum InterToken<T>: Equatable, Sendable where T: Equatable, T: Sendable {
    case literal(String)
    case interVar(T) // "interpolation variable"
}

nonisolated private enum InterpolationParserState {
    case stringLiteral
    /// The interpolation char isn't in the buffer yet: it starts a variable if `{` follows
    case interpolationCharEncountered
    case interpolationVariable
}
