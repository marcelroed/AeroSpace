import Common

/// Raw value is the precedence: `a || b && c` is `a || (b && c)`
enum ShellOp: Int, Sendable {
    case seq = 1, or, and, pipe

    var separator: String {
        switch self {
            case .seq: "; "
            case .or: " || "
            case .and: " && "
            case .pipe: " | "
        }
    }
}

indirect enum Shell<T> {
    case empty
    case cmd(T)
    /// `lhs op rhs`. A chain nests to the left: `a && b && c` is `(a && b) && c`
    case op(ShellOp, Shell<T>, Shell<T>)

    static func seq(_ elems: [Self]) -> Self { compound(.seq, elems) }
    static func or(_ elems: [Self]) -> Self { compound(.or, elems) }
    static func and(_ elems: [Self]) -> Self { compound(.and, elems) }
    static func pipe(_ elems: [Self]) -> Self { compound(.pipe, elems) }

    /// `elems` chained with `op`. No elements is `.empty`, a single element stands for itself
    static func compound(_ op: ShellOp, _ elems: [Self]) -> Self {
        guard let first = elems.first else { return .empty }
        return elems.dropFirst().reduce(first) { .op(op, $0, $1) }
    }

    func map<R, E: Error>(_ transform: (T) throws(E) -> R) throws(E) -> Shell<R> {
        switch self {
            case .empty: .empty
            case .cmd(let it): .cmd(try transform(it))
            case .op(let op, let lhs, let rhs): .op(op, try lhs.map(transform), try rhs.map(transform))
        }
    }

    /// Bounded by the parser for one expression (maxShellOperators), so the recursion is too
    var operatorCount: Int {
        switch self {
            case .empty, .cmd: 0
            case .op(_, let lhs, let rhs): 1 + lhs.operatorCount + rhs.operatorCount
        }
    }

    func flatten() -> [T] {
        switch self {
            case .empty: []
            case .cmd(let it): [it]
            case .op(_, let lhs, let rhs): lhs.flatten() + rhs.flatten()
        }
    }

    /// Every operator is associative, so an operand of the same operator needs no parentheses
    func buildDescription(_ stringifier: (T) -> String) -> String {
        switch self {
            case .empty: return ""
            case .cmd(let cmd): return stringifier(cmd)
            case .op(let op, let lhs, let rhs):
                return [lhs, rhs].map { operand in
                    let desc = operand.buildDescription(stringifier)
                    guard case .op(let operandOp, _, _) = operand, operandOp.rawValue < op.rawValue else { return desc }
                    return "(\(desc))"
                }.joined(separator: op.separator)
        }
    }
}

extension Shell: Equatable where T: Equatable {}
extension Shell: Sendable where T: Sendable {}

extension Shell where T == any Command {
    func strictEquals(_ other: Self) -> Bool {
        return switch (self, other) {
            case (.empty, .empty): true
            case (.cmd(let a), .cmd(let b)): a.equals(b)
            case (.op(let opA, let lhsA, let rhsA), .op(let opB, let lhsB, let rhsB)):
                opA == opB && lhsA.strictEquals(lhsB) && rhsA.strictEquals(rhsB)
            // Exhaustive without 'default' on purpose: a new case must be handled explicitly
            case (.empty, _), (.cmd, _), (.op, _): false
        }
    }
}

extension Shell where T == any Command {
    func run(_ env: CmdEnv, _ io: CmdIo) async -> Int32 {
        switch self {
            case .empty: return EXIT_CODE_ZERO
            case .cmd(let command):
                let exitCode = await runReportingFailure(command, env, io)
                if command.shouldResetClosedWindowsCache { resetClosedWindowsCache() }
                // The next command sees the focus callbacks' changes and a normalized tree. The callbacks' own focus
                // changes are recorded here, inside them, so they don't run the callbacks again
                await refreshModel_nonCancellable()
                return exitCode
            case .op(.seq, let lhs, let rhs):
                _ = await lhs.run(env, io)
                return await rhs.run(env, io)
            case .op(.and, let lhs, let rhs):
                let exitCode = await lhs.run(env, io)
                if exitCode != 0 { return exitCode }
                return await rhs.run(env, io)
            case .op(.or, let lhs, let rhs):
                let exitCode = await lhs.run(env, io)
                if exitCode == 0 { return exitCode }
                return await rhs.run(env, io)
            case .op(.pipe, let lhs, let rhs): return await runShellPipe(lhs, rhs, env, io)
        }
    }

    @discardableResult func run(_ env: CmdEnv, _ stdin: consuming CmdStdin) async -> CmdResult {
        let io = CmdIo(stdin: stdin)
        let exitCode = await run(env, io)
        return CmdResult(stdout: io.stdout, stderr: io.stderr, exitCode: exitCode)
    }
}

/// Runs the command one level deeper than the command that runs it, and turns its failure into stderr and an exit code
private func runReportingFailure(_ command: any Command, _ env: CmdEnv, _ io: CmdIo) async -> Int32 {
    let outer = CommandNesting.current
    let nesting = CommandNesting(command: command, depth: (outer?.depth ?? 0) + 1, tooDeep: outer?.tooDeep ?? TooDeepFlag())
    return await CommandNesting.$current.withValue(nesting) {
        do throws(CmdFail) {
            try outer?.checkCanRunNestedCommand()
            try await command.run(CmdContext(env: env, io: io))
            return EXIT_CODE_ZERO
        } catch {
            if let message = error.message { io.stderr.append(message) }
            return error.exitCode
        }
    }
}

/// Generous: configs nest a few levels. A binding or a callback that runs itself would nest without end (RB-120)
private let maxCommandNestingDepth = 32

/// The running command and how deep it nests. A binding, a callback and `eval` run their commands inside the command
/// that runs them (`trigger-binding`, `run-callback`, `mode` for on-mode-changed, `eval`), one level deeper. These
/// commands await the nested ones without an unstructured task in between, so `current` carries over to them
private struct CommandNesting {
    /// nil outside of commands
    @TaskLocal static var current: CommandNesting? = nil

    let command: any Command
    /// 1 for an outermost command, which no other command runs
    let depth: Int
    /// Shared by an outermost command and the commands nested in it
    let tooDeep: TooDeepFlag

    /// Fails a command that the running command runs, if it nests too deeply
    func checkCanRunNestedCommand() throws(CmdFail) {
        if tooDeep.isSet { throw .silent } // The command that nested too deeply has explained
        if depth < maxCommandNestingDepth { return }
        tooDeep.isSet = true
        // Names the command that runs the commands, not the innermost command: in `alt-a = ['focus left',
        // 'trigger-binding --mode main alt-a']`, that's the trigger-binding
        throw """
            Commands nest too deeply (more than \(maxCommandNestingDepth) levels). \
            A binding or callback probably runs itself: \(command.description)
            """
    }
}

/// Set when a command nests too deeply. Then the other commands nested in the same outermost command fail without
/// running. Otherwise, a binding that triggers itself twice would run 2^32 commands
private final class TooDeepFlag {
    var isSet = false
}

/// Buffers the entire stdout of `lhs`, joins it with \n and feeds it to `rhs` as stdin. AeroSpace's commands are short and
/// synchronous, so the lack of streaming doesn't matter
///
/// The semantics is similar to 'set -o pipefail': the exit code is the one of `rhs` if it's nonzero, otherwise the one of `lhs`
private func runShellPipe(_ lhs: Shell<any Command>, _ rhs: Shell<any Command>, _ env: CmdEnv, _ io: CmdIo) async -> Int32 {
    let lhsIo = CmdIo(forwardingStdinOf: io)
    let lhsExitCode = await lhs.run(env, lhsIo)
    io.stderr += lhsIo.stderr
    let rhsIo = CmdIo(stdin: .init(lhsIo.stdout.joined(separator: "\n")))
    let rhsExitCode = await rhs.run(env, rhsIo)
    io.stderr += rhsIo.stderr
    io.stdout += rhsIo.stdout
    return rhsExitCode != 0 ? rhsExitCode : lhsExitCode
}
