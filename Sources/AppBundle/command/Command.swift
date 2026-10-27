import AppKit
import Common

/// A command with its parsed arguments. `parseCommand` and `parseRequest` (parseCommand.swift) build it from words.
/// `run(_:)` is its body. To run a command, run it in a ``Shell`` (`Shell.cmd(command).run(env, stdin)` for a single
/// one), which resets the closed-windows cache and refreshes the model after each command. A command runs another one
/// with ``delegate(to:_:)``
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

/// A command's user-facing failure. `message`, if any, goes to stderr
struct CmdFail: Error, Equatable, ExpressibleByStringInterpolation {
    let message: String?
    /// Never EXIT_CODE_ZERO
    let exitCode: Int32

    init(_ message: String?) { self.init(message, exitCode: EXIT_CODE_TWO) }

    private init(_ message: String?, exitCode: Int32) {
        self.message = message
        self.exitCode = exitCode
    }

    init(stringLiteral message: String) { self.init(message) }

    /// Fail without a message: the command has already explained, or `--fail-if-noop` asked for silence
    static let silent: CmdFail = CmdFail(nil)
    /// The answer of `false` and of a `test` whose condition doesn't hold
    static let no = CmdFail(nil, exitCode: EXIT_CODE_ONE)

    /// Makes the exit code of a nested shell (`eval`, a callback, a binding) the exit code of the command
    static func passThrough(_ exitCode: Int32) throws(CmdFail) {
        if exitCode != EXIT_CODE_ZERO { throw CmdFail(nil, exitCode: exitCode) }
    }
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
    func target(windowId: WindowId? = nil, workspace: WorkspaceName? = nil) throws(CmdFail) -> LiveFocus {
        if let windowId { return try windowFocus(windowId, "passed to --window-id") }
        if let workspace { return Workspace.get(byName: workspace.raw).toLiveFocus() }
        if let windowId = env.windowId { return try windowFocus(windowId, "specified in \(AEROSPACE_WINDOW_ID) env variable") }
        if let workspace = env.workspaceName { return Workspace.get(byName: workspace).toLiveFocus() }
        return focus
    }

    /// The window of the target
    func window(windowId: WindowId?, noWindowMsg: String = noWindowIsFocused) throws(CmdFail) -> Window {
        guard let window = try target(windowId: windowId).windowOrNil else { throw CmdFail(noWindowMsg) }
        return window
    }

    private func windowFocus(_ windowId: WindowId, _ source: String) throws(CmdFail) -> LiveFocus {
        guard let window = Window.get(byId: windowId) else { throw "Invalid <window-id> \(windowId) \(source)" }
        guard let liveFocus = window.toLiveFocusOrNil() else {
            throw "Window \(windowId) doesn't belong to any monitor. And thus can't even define a focused workspace"
        }
        return liveFocus
    }
}

nonisolated let noWindowIsFocused = "No window is focused"

/// A command's AX read found the window gone
func windowClosed(_ window: Window) -> String { "Window \(window.windowId) closed" }

/// The window's native states, read from macOS. Fails if the window closed, and with another message if its app is busy:
/// a window whose read timed out isn't closed
func nativeFacts(of window: Window) async throws(CmdFail) -> NativeFacts {
    switch await world.platform.facts(window.windowId) {
        case .facts(let facts): return facts
        case .closed: throw CmdFail(windowClosed(window))
        case .noAnswer: throw CmdFail("Window \(window.windowId) didn't answer (its app is busy)")
    }
}

extension Command {
    /// Runs `command` as a part of this command, in `cx`. The only way for a command to run another command outside of
    /// a Shell: `command` gets no closed-windows cache reset and no model refresh of its own. The Shell that runs this
    /// command decides by this command's flag, so the flag must be true whenever the flag of `command` is
    func delegate<C: Command>(to command: C, _ cx: CmdContext) async throws(CmdFail) {
        assert(Self.resetsClosedWindowsCache || !C.resetsClosedWindowsCache, "\(Self.self) delegates to \(C.self), which resets the closed-windows cache")
        try await command.run(cx)
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
