import AppKit
import Common

/// A command with its parsed arguments. `parseArgs` (parseCommand.swift) builds it from words, `run` runs it
protocol Command: Equatable, Sendable {
    /// Whether running the command can change the tree, which makes the closed-windows cache stale.
    /// Deliberately without a default: every command decides
    static var resetsClosedWindowsCache: Bool { get }

    /// The words the command was parsed from
    var source: SourceWords { get set }

    /// The command as the user wrote it, e.g. in `config --get mode`. The source words by default
    var description: String { get }

    func run(_ cx: CmdContext) async throws(CmdFail)
}

/// The words a command was parsed from, the subcommand name included. They give the command back its text, e.g. in
/// `config --get mode`. They don't take part in equality: equal args make equal commands
nonisolated struct SourceWords: Equatable, Sendable, ExpressibleByArrayLiteral {
    let words: [String]
    init(_ words: [String]) { self.words = words }
    init(arrayLiteral words: String...) { self.words = words }
    static func == (_: Self, _: Self) -> Bool { true }
}

/// A command's user-facing failure. `message`, if any, goes to stderr. `test` and `false` exit with 1: a "no"
/// rather than a failure
struct CmdFail: Error, Equatable, ExpressibleByStringInterpolation {
    let message: String?
    let exitCode: Int32

    init(_ message: String?, exitCode: Int32 = EXIT_CODE_TWO) {
        self.message = message
        self.exitCode = exitCode
    }

    init(stringLiteral message: String) { self.init(message) }

    /// Fail without a message: the command has already explained, or `--fail-if-noop` asked for silence
    static let silent = CmdFail(nil)
    static let no = CmdFail(nil, exitCode: 1)
}

/// What a running command sees: the client's environment, its stdin, and where its output goes
struct CmdContext {
    let env: CmdEnv
    let io: CmdIo

    func out(_ msg: String) { io.stdout.append(msg) }
    func out(_ msg: [String]) { io.stdout += msg }
    func err(_ msg: String) { io.stderr.append(msg) }
    func readStdin() -> String { io.readStdin() }

    /// The target of the command: the --window-id or --workspace flag, then the AEROSPACE_WINDOW_ID or
    /// AEROSPACE_WORKSPACE env variable, then the focus
    func target(windowId: UInt32? = nil, workspace: WorkspaceName? = nil) throws(CmdFail) -> LiveFocus {
        if let windowId { return try windowFocus(windowId, "passed to --window-id") }
        if let workspace { return Workspace.get(byName: workspace.raw).toLiveFocus() }
        if let windowId = env.windowId { return try windowFocus(windowId, "specified in \(AEROSPACE_WINDOW_ID) env variable") }
        if let workspace = env.workspaceName { return Workspace.get(byName: workspace).toLiveFocus() }
        return focus
    }

    /// The window of the target
    func window(windowId: UInt32?, noWindowMsg: String = noWindowIsFocused) throws(CmdFail) -> Window {
        guard let window = try target(windowId: windowId).windowOrNil else { throw CmdFail(noWindowMsg) }
        return window
    }

    private func windowFocus(_ windowId: UInt32, _ source: String) throws(CmdFail) -> LiveFocus {
        guard let window = Window.get(byId: windowId) else { throw "Invalid <window-id> \(windowId) \(source)" }
        guard let liveFocus = window.toLiveFocusOrNil() else {
            throw "Window \(windowId) doesn't belong to any monitor. And thus can't even define a focused workspace"
        }
        return liveFocus
    }
}

nonisolated let noWindowIsFocused = "No window is focused"

extension Command {
    /// Runs the command, and turns its failure into stderr and an exit code
    func run(_ env: CmdEnv, _ io: CmdIo) async -> Int32 {
        do {
            try await run(CmdContext(env: env, io: io))
            return EXIT_CODE_ZERO
        } catch {
            if let message = error.message { io.stderr.append(message) }
            return error.exitCode
        }
    }

    @discardableResult
    func run(_ env: CmdEnv, _ stdin: consuming CmdStdin) async -> CmdResult {
        await Shell.cmd(self).run(env, stdin)
    }

    var shouldResetClosedWindowsCache: Bool { Self.resetsClosedWindowsCache }

    func equals(_ other: any Command) -> Bool { (other as? Self) == self }

    var description: String { source.words.joinArgs() }
}

/// The result of `--fail-if-noop` when there is nothing to do: fail silently, or succeed and say why nothing happened
func noop(_ cx: CmdContext, failIfNoop: Bool, _ msg: @autoclosure () -> String) throws(CmdFail) {
    if failIfNoop { throw .silent }
    cx.err(msg())
}
