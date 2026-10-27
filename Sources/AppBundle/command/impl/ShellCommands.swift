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

struct RunCallbackCommand: nonisolated Command {
    nonisolated enum CallbackKind: String, CaseIterable, Equatable, Sendable {
        case onWindowDetected = "on-window-detected"
        case onFocusChanged = "on-focus-changed"
        case onFocusedMonitorChanged = "on-focused-monitor-changed"
    }

    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var callback: CallbackKind
    var forEveryWindow = false
    var windowId: UInt32? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var forEveryWindow = false
        var windowId: UInt32? = nil
        while let option = try a.nextOption() {
            switch option {
                case "--for-every-window": forEveryWindow = true
                case "--window-id": windowId = try a.windowId(of: option)
                default: throw .unknownOption(option)
            }
        }
        let callback: CallbackKind = try parseEnum(a.positional("<callback>"))
        try a.end()
        if forEveryWindow && windowId != nil { throw .conflicting("--for-every-window", "--window-id") }
        if forEveryWindow && callback != .onWindowDetected { throw "--for-every-window is only allowed with 'on-window-detected'" }
        if windowId != nil && callback != .onWindowDetected { throw "--window-id is only allowed with 'on-window-detected'" }
        return Self(callback: callback, forEveryWindow: forEveryWindow, windowId: windowId)
    }

    /// Exits with the exit code of the callback
    func run(_ cx: CmdContext) async throws(CmdFail) {
        let target = try cx.target(windowId: windowId)
        let exitCode: Int32
        switch callback {
            case .onWindowDetected where forEveryWindow:
                exitCode = await onWindowDetected(cx.env, cx.io, forEvery: MacWindow.allWindows)
            case .onWindowDetected:
                guard let window = target.windowOrNil else { throw CmdFail(noWindowIsFocused) }
                exitCode = await onWindowDetected(cx.env, cx.io, window)
            case .onFocusChanged:
                exitCode = await onFocusChanged(cx.env, cx.io, target)
            case .onFocusedMonitorChanged:
                exitCode = await onFocusedMonitorChanged(cx.env, cx.io, target)
        }
        if exitCode != EXIT_CODE_ZERO { throw CmdFail(nil, exitCode: exitCode) }
    }
}

/// `windows` is a parameter because tests can't create a `MacWindow`
func onWindowDetected(_ env: CmdEnv, _ io: CmdIo, forEvery windows: [Window]) async -> Int32 {
    var exitCode = EXIT_CODE_ZERO
    for window in windows.sortedBy({ $0.windowId }) where window.shouldRunOnWindowDetected {
        let windowExitCode = await onWindowDetected(env, io, window)
        if exitCode == EXIT_CODE_ZERO { exitCode = windowExitCode } // Report the first failure
    }
    return exitCode
}

struct EchoCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var args: [[FormatToken]]
    var isStderr = false
    var windowId: UInt32? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var isStderr = false
        var windowId: UInt32? = nil
        while let option = try a.nextOption() {
            switch option {
                case "--stderr": isStderr = true
                case "--window-id": windowId = try a.windowId(of: option)
                default: throw .unknownOption(option)
            }
        }
        let args = try a.allPositionals().map(parseFormat)
        if args.isEmpty { throw "Argument '<string>' is mandatory" }
        return Self(args: args, isStderr: isStderr, windowId: windowId)
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let target = try cx.target(windowId: windowId)
        let obj: AeroObj
        if let window = target.windowOrNil {
            guard let window = try? await WindowWithPrefetchedTitle.resolveWindow(window, for: args.flatMap { $0 }, .nonCancellable) else {
                throw CmdFail(bugPrompt())
            }
            obj = .window(window)
        } else {
            obj = .workspace(target.workspace)
        }
        for arg in args {
            let line: String
            do {
                line = try obj.format(arg)
            } catch {
                throw CmdFail(error.cmdErrorMessage)
            }
            if isStderr { cx.err(line) } else { cx.out(line) }
        }
    }
}

struct EvalCommand: nonisolated Command {
    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var shellExpr: String

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        while let option = try a.nextOption() {
            switch option {
                case "--stdin": break // For the CLI: it sends its stdin, which the commands of the expression can read
                default: throw .unknownOption(option)
            }
        }
        let result = Self(shellExpr: try a.positional("<aerospace-shell-expr>"))
        try a.end()
        return result
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let shell: Shell<any Command>
        do {
            shell = try parseShell(shellExpr, allowExecAndForget: false, allowEval: false)
        } catch .help {
            throw "--help is not supported inside eval command"
        } catch {
            throw CmdFail(error.message)
        }
        let exitCode = await shell.run(cx.env, cx.io)
        if exitCode != EXIT_CODE_ZERO { throw CmdFail(nil, exitCode: exitCode) }
    }
}

/// Only the config knows it: the rest of the line after the name is a bash script (parseShell)
struct ExecAndForgetCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    let bashScript: String

    /// The script isn't a word: it's the rest of the line, unquoted
    var description: String { "exec-and-forget" + bashScript }

    func run(_ cx: CmdContext) throws(CmdFail) {
        // todo shall exec-and-forget fork exec session?
        // It doesn't throw if exit code is non-zero
        let process = Process()
        process.environment = config.execConfig.envVariables + cx.env.asMap
        process.executableURL = URL(filePath: "/bin/bash")
        process.arguments = ["-c", bashScript]
        if (try? process.run()) == nil { throw .silent }
    }
}

struct ModeCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var targetMode: String

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        try a.noOptions()
        let result = Self(targetMode: try a.positional("<binding-mode>"))
        try a.end()
        return result
    }

    func run(_ cx: CmdContext) async {
        await activateMode_nonCancellable(targetMode)
    }
}

struct TriggerBindingCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var mode: String
    var binding: String

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var mode: String? = nil
        while let option = try a.nextOption() {
            switch option {
                case "--mode": mode = try a.value(of: option, "<mode-id>")
                default: throw .unknownOption(option)
            }
        }
        guard let mode else { throw "--mode flag is mandatory" }
        let result = Self(mode: mode, binding: try a.positional("<binding>"))
        try a.end()
        return result
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        guard let modeBindings = config.modes[mode]?.bindings else {
            throw "Mode '\(mode)' doesn't exist. Available modes: \(config.modes.keys.sorted().joined(separator: ","))"
        }
        guard let match = modeBindings.values.first(where: { $0.descriptionWithKeyNotation == binding }) else {
            throw "Binding '\(binding)' is not presented in mode '\(mode)'"
        }
        // refreshSession is not needed since commands are already run in refreshSession
        let exitCode = await match.commands.run(cx.env, cx.io)
        if exitCode != EXIT_CODE_ZERO { throw CmdFail(nil, exitCode: exitCode) }
    }
}

struct TrueCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        try a.noArgs()
        return Self()
    }

    func run(_ cx: CmdContext) {}
}

struct FalseCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        try a.noArgs()
        return Self()
    }

    func run(_ cx: CmdContext) throws(CmdFail) { throw .no }
}
