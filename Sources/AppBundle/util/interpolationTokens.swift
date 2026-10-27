import Common

extension String {
    /// The tokens of a string with interpolation variables: `%{window-id}` in a format, `${HOME}` in an exec env variable
    nonisolated func rawInterpolationTokens(interpolationChar: Character) throws(CmdParseError) -> [InterToken<String>] {
        var mode: InterpolationParserState = .stringLiteral(currLiteral: "")
        var result: [InterToken<String>] = []
        for char: Character? in (Array(self) + [nil]) {
            switch (mode, char) { // State machine
                case (.stringLiteral(let literal), interpolationChar):
                    mode = .interpolationCharEncountered(prevLiteral: literal)
                case (.stringLiteral(let literal), let char?):
                    mode = .stringLiteral(currLiteral: literal + String(char))
                case (.stringLiteral(let literal), nil):
                    result.append(.literal(literal))
                case (.interpolationCharEncountered(let literal), "{"):
                    mode = .interpolationVariable(currVariable: "")
                    result.append(.literal(literal))
                case (.interpolationCharEncountered(let literal), interpolationChar):
                    mode = .interpolationCharEncountered(prevLiteral: literal + String(interpolationChar))
                case (.interpolationCharEncountered(let literal), let char?):
                    mode = .stringLiteral(currLiteral: literal + String(interpolationChar) + String(char))
                case (.interpolationCharEncountered(let literal), nil):
                    result.append(.literal(literal + String(interpolationChar)))
                case (.interpolationVariable(let value), "}"):
                    result.append(.interVar(value))
                    mode = .stringLiteral(currLiteral: "")
                case (.interpolationVariable(let value), "{"):
                    throw "Can't parse '\(value + "{")' inside interpolation (Open curly brace is invalid character)"
                case (.interpolationVariable(let value), interpolationChar):
                    throw "Can't parse '\(value + .init(interpolationChar))' inside interpolation ('\(interpolationChar)' is disallowed character)"
                case (.interpolationVariable(let value), let char?):
                    mode = .interpolationVariable(currVariable: value + .init(char))
                case (.interpolationVariable, nil):
                    throw "Unbalanced curly braces"
            }
        }
        return result.filter { $0 != .literal("") }
    }
}

nonisolated enum InterToken<T>: Equatable, Sendable where T: Equatable, T: Sendable {
    case literal(String)
    case interVar(T) // "interpolation variable"
}

nonisolated private enum InterpolationParserState {
    case stringLiteral(currLiteral: String)
    case interpolationCharEncountered(prevLiteral: String)
    case interpolationVariable(currVariable: String)
}
