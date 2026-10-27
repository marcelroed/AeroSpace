import AppKit
import Common

/// The workspace argument of `workspace` and `move-node-to-workspace`
nonisolated enum WorkspaceArg {
    case relative(NextPrev)
    case direct(WorkspaceName)

    static let placeholder = "(<workspace-name>|next|prev)"

    /// `next` and `prev` are keywords, unless they come after `--`
    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        let (arg, isLiteral) = try a.positionalAndIsLiteral(placeholder)
        if !isLiteral, let nextPrev = NextPrev(rawValue: arg) { return .relative(nextPrev) }
        return .direct(try WorkspaceName.parse(arg))
    }
}

struct WorkspaceCommand: nonisolated Command {
    /// Each target carries the options that apply to it
    nonisolated enum Target: Equatable, Sendable {
        case relative(NextPrev, wrapAround: Bool = false, useStdin: Bool = false)
        case direct(WorkspaceName, whenFocused: WhenFocused = .noop)
    }

    /// What `workspace <name>` does when the workspace is already focused
    nonisolated enum WhenFocused: Equatable, Sendable {
        case noop
        /// `--fail-if-noop`
        case fail
        /// `--auto-back-and-forth`
        case backAndForth
    }

    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var target: Target

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var autoBackAndForth = false
        var wrapAround = false
        var failIfNoop = false
        var useStdin = false
        while let option = try a.nextOption() {
            switch option {
                case "--auto-back-and-forth": autoBackAndForth = true
                case "--wrap-around": wrapAround = true
                case "--fail-if-noop": failIfNoop = true
                case "--stdin": useStdin = true
                default: throw .unknownOption(option)
            }
        }
        let arg = try WorkspaceArg.parse(&a)
        try a.end()
        switch arg {
            case .relative(let nextPrev):
                if autoBackAndForth { throw "--auto-back-and-forth is incompatible with \(NextPrev.unionLiteral)" }
                if failIfNoop { throw "--fail-if-noop is incompatible with \(NextPrev.unionLiteral)" }
                return Self(target: .relative(nextPrev, wrapAround: wrapAround, useStdin: useStdin))
            case .direct(let name):
                if wrapAround { throw "--wrap-around requires using \(NextPrev.unionLiteral) argument" }
                if autoBackAndForth && failIfNoop { throw "--fail-if-noop is incompatible with --auto-back-and-forth" }
                if useStdin { throw "--stdin requires using \(NextPrev.unionLiteral) argument" }
                return Self(target: .direct(name, whenFocused: autoBackAndForth ? .backAndForth : failIfNoop ? .fail : .noop))
        }
    }

    func run(_ cx: CmdContext) async throws(CmdFail) { // todo refactor
        let focusedWs = try cx.target().workspace
        let workspaceName: String
        let failIfNoop: Bool
        switch target {
            case .relative(let nextPrev, let wrapAround, let useStdin):
                workspaceName = try getNextPrevWorkspace(
                    current: focusedWs,
                    isNext: nextPrev == .next,
                    wrapAround: wrapAround,
                    stdin: useStdin ? cx.readStdin() : nil,
                ).name
                failIfNoop = false
            case .direct(let name, let whenFocused):
                workspaceName = name.raw
                if whenFocused == .backAndForth && focusedWs.name == workspaceName {
                    return try await delegate(to: WorkspaceBackAndForthCommand(), cx)
                }
                failIfNoop = whenFocused == .fail
        }
        if focusedWs.name == workspaceName {
            return try noop(cx, failIfNoop: failIfNoop, "Workspace '\(workspaceName)' is already focused. Tip: use --fail-if-noop to exit with non-zero code")
        }
        try Workspace.get(byName: workspaceName).focusWorkspaceOrFail()
    }
}

extension Workspace {
    /// Focusing a workspace fails only while there are no screens, if it isn't visible
    func focusWorkspaceOrFail() throws(CmdFail) {
        if !focusWorkspace() { throw "Can't focus workspace '\(name)' while there are no screens" }
    }
}

func getNextPrevWorkspace(current: Workspace, isNext: Bool, wrapAround: Bool, stdin: String?) throws(CmdFail) -> Workspace {
    let stdinWorkspaces: [WorkspaceName]
    do {
        stdinWorkspaces = try (stdin ?? "").split(whereSeparator: \.isWhitespace)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(WorkspaceName.parse)
    } catch {
        throw CmdFail(error.message)
    }
    let currentMonitor = current.workspaceMonitor
    let workspaces: [Workspace] = stdin != nil
        ? stdinWorkspaces.map { Workspace.get(byName: $0.raw) }
        : Workspace.all.filter { $0.workspaceMonitor.rect.topLeftCorner == currentMonitor.rect.topLeftCorner }
            .toSet()
            .union([current])
            .sorted()
    if workspaces.isEmpty { throw "The list of workspaces is empty" }
    let index = workspaces.firstIndex(where: { $0 == current })
        .map { index in isNext ? index + 1 : index - 1 }
        ?? 0
    if wrapAround {
        guard let workspace = workspaces.get(wrappingIndex: index) else { throw "List of workspaces is empty" }
        return workspace
    }
    guard let workspace = workspaces.getOrNil(atIndex: index) else {
        throw CmdFail(index >= workspaces.count
            ? "Reached the end of the supplied workspaces list"
            : "Reached the beginning of the supplied workspaces list")
    }
    return workspace
}

struct WorkspaceBackAndForthCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        try a.noArgs()
        return Self()
    }

    func run(_ cx: CmdContext) throws(CmdFail) {
        guard let prevFocusedWorkspace else { throw "There is no previously focused workspace" }
        try prevFocusedWorkspace.focusWorkspaceOrFail()
    }
}

struct SummonWorkspaceCommand: nonisolated Command {
    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var target: WorkspaceName
    var failIfNoop = false

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var failIfNoop = false
        while let option = try a.nextOption() {
            switch option {
                case "--fail-if-noop": failIfNoop = true
                default: throw .unknownOption(option)
            }
        }
        let target = try WorkspaceName.parse(a.positional("<workspace>"))
        try a.end()
        return Self(target: target, failIfNoop: failIfNoop)
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        // No screens (e.g., during display reconfiguration): don't show other workspaces on the monitors that macOS doesn't
        // report meanwhile, like setFocus
        if !world.monitors.hasScreens { throw "Can't summon workspace '\(target.raw)' while there are no screens" }
        let workspace = Workspace.get(byName: target.raw)
        let monitor = focus.workspace.workspaceMonitor
        if monitor.activeWorkspace == workspace {
            return try noop(cx, failIfNoop: failIfNoop, "Workspace '\(workspace.name)' is already visible on the focused monitor. Tip: use --fail-if-noop to exit with non-zero code")
        }
        try moveWorkspace(workspace, to: monitor)
        try workspace.focusWorkspaceOrFail()
    }
}
