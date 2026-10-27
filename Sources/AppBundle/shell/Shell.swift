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

// There are 4 entry points for running commands:
// 1. config keybindings
// 2. CLI requests to server
// 3. on-window-detected callback
// 4. Tray icon buttons
extension Shell where T == any Command {
    func run(_ env: CmdEnv, _ io: CmdIo) async -> Int32 {
        switch self {
            case .empty: return EXIT_CODE_ZERO
            case .cmd(let command):
                let exitCode = await command.run(env, io)
                if command.shouldResetClosedWindowsCache { resetClosedWindowsCache() }
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
