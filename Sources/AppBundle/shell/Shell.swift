import Common

indirect enum Shell<T> {
    case empty
    case cmd(T)

    // Listed in precedence order
    case pipe([Shell<T>])
    case and([Shell<T>])
    case or([Shell<T>])
    case seq([Shell<T>])

    static func newCompound(_ elems: [Self], _ constructor: ([Self]) -> Self) -> Self {
        switch elems.count {
            case 0: .empty
            case 1: elems[0]
            default: constructor(elems)
        }
    }

    func flatMap<R>(_ mapper: (T) -> ParsedCmd<R>) -> ParsedCmd<Shell<R>> {
        switch self {
            case .empty: return .cmd(.empty)
            case .cmd(let it): return mapper(it).map(Shell<R>.cmd)
            case .and(let it): return it.mapAllOrFailure { $0.flatMap(mapper) }.map(Shell<R>.and)
            case .or(let it): return it.mapAllOrFailure { $0.flatMap(mapper) }.map(Shell<R>.or)
            case .pipe(let it): return it.mapAllOrFailure { $0.flatMap(mapper) }.map(Shell<R>.pipe)
            case .seq(let it): return it.mapAllOrFailure { $0.flatMap(mapper) }.map(Shell<R>.seq)
        }
    }

    func flatten() -> [T] {
        switch self {
            case .empty: []
            case .cmd(let it): [it]
            case .pipe(let it), .and(let it), .or(let it), .seq(let it): it.flatMap { $0.flatten() }
        }
    }

    func buildDescription(_ stringifier: (T) -> String) -> String {
        let parentPrecedence = precedence
        func render(_ child: Shell<T>) -> String {
            let desc = child.buildDescription(stringifier)
            return child.precedence < parentPrecedence ? "(\(desc))" : desc
        }
        return switch self {
            case .empty: ""
            case .cmd(let cmd): stringifier(cmd)
            case .pipe(let it): it.map(render).joined(separator: " | ")
            case .and(let it): it.map(render).joined(separator: " && ")
            case .or(let it): it.map(render).joined(separator: " || ")
            case .seq(let it): it.map(render).joined(separator: "; ")
        }
    }

    private var precedence: Int {
        switch self {
            case .empty, .cmd: Int.max
            case .pipe: 4
            case .and: 3
            case .or: 2
            case .seq: 1
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
            case (.pipe(let a), .pipe(let b)), (.and(let a), .and(let b)), (.or(let a), .or(let b)), (.seq(let a), .seq(let b)):
                a.count == b.count && zip(a, b).allSatisfy { a, b in a.strictEquals(b) }
            // Exhaustive without 'default' on purpose: a new case must be handled explicitly
            case (.empty, _), (.cmd, _), (.pipe, _), (.and, _), (.or, _), (.seq, _): false
        }
    }
}

// There are 4 entry points for running commands:
// 1. config keybindings
// 2. CLI requests to server
// 3. on-window-detected callback
// 4. Tray icon buttons
extension Shell where T == any Command {
    func run(_ env: CmdEnv, _ io: CmdIo) async -> Int32ExitCode {
        switch self {
            case .empty: return Int32ExitCode(rawValue: EXIT_CODE_ZERO)
            case .cmd(let command):
                let exitCode = Int32ExitCode(rawValue: await command.run(env, io).rawValue)
                if command.shouldResetClosedWindowsCache { resetClosedWindowsCache() }
                await refreshModel_nonCancellable()
                return exitCode
            case .pipe(let commands): return await runShellPipe(commands, env, io)
            case .and(let commands): return await runSequentially(commands, env, io, initial: EXIT_CODE_ZERO) { $0 != 0 }
            case .or(let commands): return await runSequentially(commands, env, io, initial: EXIT_CODE_TWO) { $0 == 0 }
            case .seq(let commands): return await runSequentially(commands, env, io, initial: EXIT_CODE_ZERO) { _ in false }
        }
    }

    @discardableResult func run(_ env: CmdEnv, _ stdin: consuming CmdStdin) async -> CmdResult {
        let io = CmdIo(stdin: stdin)
        let exitCode = await run(env, io)
        return CmdResult(stdout: io.stdout, stderr: io.stderr, exitCode: exitCode)
    }
}

/// Runs `commands` in order and stops after the first exit code for which `stop` is true
private func runSequentially(_ commands: [Shell<any Command>], _ env: CmdEnv, _ io: CmdIo, initial: Int32, stop: (Int32) -> Bool) async -> Int32ExitCode {
    var exitCode = Int32ExitCode(rawValue: initial)
    for command in commands {
        exitCode = await command.run(env, io)
        if stop(exitCode.rawValue) { break }
    }
    return exitCode
}

/// runs commands sequentially, buffering the entire stdout between them and joining with \n before re-feeding as stdin.
/// For long-running or streaming commands this would matter, but AeroSpace's commands are short and synchronous, so this is fine
///
/// The semantics is similar to 'set -o pipefail'
private func runShellPipe(_ commands: [Shell<any Command>], _ env: CmdEnv, _ originalIo: CmdIo) async -> Int32ExitCode {
    var rightmostNonZeroExitCode = Int32ExitCode(rawValue: EXIT_CODE_ZERO)
    var io = CmdIo(forwardingStdinOf: originalIo)
    var lastStdout = [String]()
    for command in commands {
        let exitCode = await command.run(env, io)
        originalIo.stderr += io.stderr
        lastStdout = io.stdout
        io = CmdIo(stdin: .init(lastStdout.joined(separator: "\n")))
        if exitCode.rawValue != 0 {
            rightmostNonZeroExitCode = exitCode
        }
    }
    originalIo.out(lastStdout)
    return rightmostNonZeroExitCode
}
