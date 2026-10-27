import Foundation

extension String {
    public func prefixLines(with: String) -> String {
        split(separator: "\n", omittingEmptySubsequences: false).map { with + $0 }.joined(separator: "\n")
    }

    public var singleQuoted: String { "'" + self + "'" }
    public var doubleQuoted: String { "\"" + self + "\"" }
}

extension [String] {
    public func joinTruncating(separator: String, length maxLength: Int, trailing: String = "…") -> String {
        if isEmpty {
            return ""
        }
        var result: String = first.orDie()
        if result.count > maxLength {
            return result.prefix(maxLength) + trailing
        }
        var remainingLen = maxLength - result.count
        let separatorCount = separator.count
        for _elem in self.dropFirst() {
            let elemCount = separatorCount + _elem.count
            if remainingLen < elemCount / 2 {
                return result + separator + trailing
            }
            let elem = separator + _elem
            if elemCount <= remainingLen {
                result += elem
                remainingLen -= elemCount
            } else {
                return result + elem.prefix(remainingLen) + trailing
            }
        }
        return result
    }
}

extension [[String]] {
    public func toPaddingTable(columnSeparator: String = " | ") -> [String] {
        let pads: [Int] = transposed().map { column in column.map { $0.count }.max().orDie() }
        return self.map { (row: [String]) in
            zip(row.enumerated(), pads)
                .map { (elem: (Int, String), pad: Int) in
                    elem.0 != row.count - 1 ? elem.1 + String(repeating: " ", count: pad - elem.1.count) : elem.1
                }
                .joined(separator: columnSeparator)
        }
    }
}


extension String {
    public func rawInterpolationTokens(interpolationChar: Character) throws(CmdParseError) -> [InterToken<String>] {
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

public enum InterToken<T>: Equatable, Sendable where T: Equatable, T: Sendable {
    case literal(String)
    case interVar(T) // "interpolation variable"
}

private enum InterpolationParserState {
    case stringLiteral(currLiteral: String)
    case interpolationCharEncountered(prevLiteral: String)
    case interpolationVariable(currVariable: String)
}
