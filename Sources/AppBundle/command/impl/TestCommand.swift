import AppKit
import Common

struct TestCommand: Command {
    let args: TestCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache: Bool = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> ConditionalExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }

        let lhs: Result<Primitive, InterVarExpansionError>
        switch target.windowOrNil {
            case let window?:
                guard let window = try? await WindowWithPrefetchedTitle.resolveWindow(window, for: args.lhs.val, .nonCancellable) else { return .fail(io.err(bugPrompt())) }
                lhs = args.lhs.val.expandFormatVar(obj: .window(window))
            case nil:
                lhs = args.lhs.val.expandFormatVar(obj: .workspace(target.workspace))
        }

        guard let lhs = lhs.getOrNil(onFailure: { err in io.err(err.cmdErrorMessage) }) else { return .fail }

        let infixOperator = args.infixOperator.val
        let rhs = args.rhs.val
        let lhsType = lhs.kind.rawValue
        let incompatibleLhsAndOperatorMsg = """
            Interpolation variable: \(args.lhs.val.rawValue.singleQuoted) has a type of \(lhsType). The \(lhsType) type is not compatible with \(infixOperator.rawValue.singleQuoted) operator.
            """

        let result: Result<Bool, String> = switch (lhs, infixOperator) {
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

        return switch result {
            case .success(let result): result ? ._true : ._false
            case .failure(let err): .fail(io.err(err))
        }
    }
}
