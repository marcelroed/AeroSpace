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
    case op(ShellOp, [Shell<T>])

    static func seq(_ elems: [Self]) -> Self { .op(.seq, elems) }
    static func or(_ elems: [Self]) -> Self { .op(.or, elems) }
    static func and(_ elems: [Self]) -> Self { .op(.and, elems) }
    static func pipe(_ elems: [Self]) -> Self { .op(.pipe, elems) }

    /// No elements is `.empty`, a single element stands for itself
    static func compound(_ op: ShellOp, _ elems: [Self]) -> Self {
        switch elems.count {
            case 0: .empty
            case 1: elems[0]
            default: .op(op, elems)
        }
    }

    func map<R, E: Error>(_ transform: (T) throws(E) -> R) throws(E) -> Shell<R> {
        switch self {
            case .empty: .empty
            case .cmd(let it): .cmd(try transform(it))
            case .op(let op, let it): .op(op, try it.map { (it) throws(E) in try it.map(transform) })
        }
    }

    func flatten() -> [T] {
        switch self {
            case .empty: []
            case .cmd(let it): [it]
            case .op(_, let it): it.flatMap { $0.flatten() }
        }
    }

    func buildDescription(_ stringifier: (T) -> String) -> String {
        switch self {
            case .empty: return ""
            case .cmd(let cmd): return stringifier(cmd)
            case .op(let op, let children):
                return children.map { child in
                    let desc = child.buildDescription(stringifier)
                    guard case .op(let childOp, _) = child, childOp.rawValue < op.rawValue else { return desc }
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
            case (.op(let opA, let a), .op(let opB, let b)):
                opA == opB && a.count == b.count && zip(a, b).allSatisfy { a, b in a.strictEquals(b) }
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
            case .op(.pipe, let commands): return await runShellPipe(commands, env, io)
            case .op(.and, let commands): return await runSequentially(commands, env, io, initial: EXIT_CODE_ZERO) { $0 != 0 }
            case .op(.or, let commands): return await runSequentially(commands, env, io, initial: EXIT_CODE_TWO) { $0 == 0 }
            case .op(.seq, let commands): return await runSequentially(commands, env, io, initial: EXIT_CODE_ZERO) { _ in false }
        }
    }

    @discardableResult func run(_ env: CmdEnv, _ stdin: consuming CmdStdin) async -> CmdResult {
        let io = CmdIo(stdin: stdin)
        let exitCode = await run(env, io)
        return CmdResult(stdout: io.stdout, stderr: io.stderr, exitCode: exitCode)
    }
}

/// Runs `commands` in order and stops after the first exit code for which `stop` is true
private func runSequentially(_ commands: [Shell<any Command>], _ env: CmdEnv, _ io: CmdIo, initial: Int32, stop: (Int32) -> Bool) async -> Int32 {
    var exitCode = initial
    for command in commands {
        exitCode = await command.run(env, io)
        if stop(exitCode) { break }
    }
    return exitCode
}

/// runs commands sequentially, buffering the entire stdout between them and joining with \n before re-feeding as stdin.
/// For long-running or streaming commands this would matter, but AeroSpace's commands are short and synchronous, so this is fine
///
/// The semantics is similar to 'set -o pipefail'
private func runShellPipe(_ commands: [Shell<any Command>], _ env: CmdEnv, _ originalIo: CmdIo) async -> Int32 {
    var rightmostNonZeroExitCode = EXIT_CODE_ZERO
    var io = CmdIo(forwardingStdinOf: originalIo)
    var lastStdout = [String]()
    for command in commands {
        let exitCode = await command.run(env, io)
        originalIo.stderr += io.stderr
        lastStdout = io.stdout
        io = CmdIo(stdin: .init(lastStdout.joined(separator: "\n")))
        if exitCode != 0 {
            rightmostNonZeroExitCode = exitCode
        }
    }
    originalIo.stdout += lastStdout
    return rightmostNonZeroExitCode
}
