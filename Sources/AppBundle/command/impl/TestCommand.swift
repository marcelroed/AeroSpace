import AppKit
import Common

/// `test` and `test-not`
struct TestCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var negated: Bool
    var lhs: FormatVar
    var infixOperator: InfixOperator
    var rhs: String

    nonisolated enum InfixOperator: String, CaseIterable, Sendable {
        case equals = "="
        case matchesRegex = "~="
    }

    static func parse(_ a: inout ArgCursor, negated: Bool) throws(CmdParseError) -> Self {
        try a.noOptions()
        let lhs = try parseLhs(a.positional("<lhs>"))
        let infixOperator: InfixOperator = try parseEnum(a.positional("<operator>"))
        let rhs = try a.positional("<rhs>")
        try a.end()
        guard case .literal(let rhsLiteral) = try rawTokens(rhs).singleOrNil() else {
            throw "Right hand side doesn't allow interpolation variables"
        }
        return Self(negated: negated, lhs: lhs, infixOperator: infixOperator, rhs: rhsLiteral)
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let target = try cx.target()
        let obj: AeroObj
        if let window = target.windowOrNil {
            guard let window = try? await WindowWithPrefetchedTitle.resolveWindow(window, for: [.interVar(lhs)], .nonCancellable) else {
                throw CmdFail(bugPrompt())
            }
            obj = .window(window)
        } else {
            obj = .workspace(target.workspace)
        }
        let lhsValue: Primitive
        do {
            lhsValue = try lhs.expand(obj)
        } catch {
            throw CmdFail(error.cmdErrorMessage)
        }

        let lhsType = lhsValue.kind.rawValue
        let incompatibleLhsAndOperatorMsg = """
            Interpolation variable: \(lhs.rawValue.singleQuoted) has a type of \(lhsType). The \(lhsType) type is not compatible with \(infixOperator.rawValue.singleQuoted) operator.
            """

        let result: Result<Bool, String> = switch (lhsValue, infixOperator) {
            case (.bool(let lhs), .equals):
                Bool(rhs).toResult("Can't convert String \(rhs.singleQuoted) to Bool").map { rhs in lhs == rhs }
            case (.int(let lhs), .equals):
                Int64(rhs).toResult("Can't convert String \(rhs.singleQuoted) to Int").map { rhs in lhs == rhs }
            case (.bool, .matchesRegex), (.int, .matchesRegex):
                .failure(incompatibleLhsAndOperatorMsg)
            case (.string(let lhs), .equals):
                .success(lhs == rhs)
            case (.string(let lhs), .matchesRegex):
                CaseInsensitiveRegex.new(rhs).map { rhs in lhs.contains(caseInsensitiveRegex: rhs) }
        }

        switch result {
            case .success(let result): if result == negated { throw .no }
            case .failure(let err): throw CmdFail(err)
        }
    }
}

/// The left hand side: a single variable about an object, not a formatting one
private func parseLhs(_ raw: String) throws(CmdParseError) -> FormatVar {
    let objectVars = FormatVar.allCases.filter { $0.subject != nil }
    let tokens = try rawTokens(raw).map { (token) throws(CmdParseError) -> InterToken<FormatVar> in
        switch token {
            case .literal(let literal): return .literal(literal)
            case .interVar(let name):
                guard let formatVar = objectVars.first(where: { $0.rawValue == name }) else {
                    throw "Can't parse '\(name)'.\nPossible values: (\(objectVars.map(\.rawValue).joined(separator: "|")))"
                }
                return .interVar(formatVar)
        }
    }
    guard case .interVar(let formatVar) = tokens.singleOrNil() else { throw "Left hand side must be a single interpolation variable" }
    return formatVar
}

private func rawTokens(_ raw: String) throws(CmdParseError) -> [InterToken<String>] {
    switch raw.rawInterpolationTokens(interpolationChar: "%") {
        case .success(let tokens): tokens
        case .failure(let msg): throw .invalid(msg)
    }
}
