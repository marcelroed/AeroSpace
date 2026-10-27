import AppKit
import Common

/// The workspace of `workspace` and `move-node-to-workspace`
nonisolated enum WorkspaceTarget: Equatable, Sendable {
    case relative(NextPrev)
    case direct(WorkspaceName)

    static let placeholder = "(<workspace-name>|next|prev)"

    /// `next` and `prev` are keywords, unless they come after `--`
    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        let (arg, isLiteral) = try a.positionalAndIsLiteral(placeholder)
        if !isLiteral, let nextPrev = NextPrev(rawValue: arg) { return .relative(nextPrev) }
        return .direct(try parseWorkspaceName(arg))
    }

    var isRelative: Bool {
        switch self {
            case .relative: true
            case .direct: false
        }
    }
}

struct WorkspaceCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var target: WorkspaceTarget
    var autoBackAndForth = false
    var wrapAround = false
    var failIfNoop = false
    var useStdin = false

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
        let target = try WorkspaceTarget.parse(&a)
        try a.end()
        let relative = target.isRelative
        if wrapAround && !relative { throw "--wrap-around requires using \(NextPrev.unionLiteral) argument" }
        if autoBackAndForth && relative { throw "--auto-back-and-forth is incompatible with \(NextPrev.unionLiteral)" }
        if failIfNoop && relative { throw "--fail-if-noop is incompatible with \(NextPrev.unionLiteral)" }
        if autoBackAndForth && failIfNoop { throw "--fail-if-noop is incompatible with --auto-back-and-forth" }
        if useStdin && !relative { throw "--stdin requires using \(NextPrev.unionLiteral) argument" }
        return Self(target: target, autoBackAndForth: autoBackAndForth, wrapAround: wrapAround, failIfNoop: failIfNoop, useStdin: useStdin)
    }

    func run(_ cx: CmdContext) async throws(CmdFail) { // todo refactor
        let focusedWs = try cx.target().workspace
        let workspaceName: String
        switch target {
            case .relative(let nextPrev):
                workspaceName = try getNextPrevWorkspace(
                    current: focusedWs,
                    isNext: nextPrev == .next,
                    wrapAround: wrapAround,
                    stdin: useStdin ? cx.readStdin() : nil,
                ).name
            case .direct(let name):
                workspaceName = name.raw
                if autoBackAndForth && focusedWs.name == workspaceName {
                    return try WorkspaceBackAndForthCommand().run(cx)
                }
        }
        if focusedWs.name == workspaceName {
            return try noop(cx, failIfNoop: failIfNoop, "Workspace '\(workspaceName)' is already focused. Tip: use --fail-if-noop to exit with non-zero code")
        }
        if !Workspace.get(byName: workspaceName).focusWorkspace() { throw .silent }
    }
}

func getNextPrevWorkspace(current: Workspace, isNext: Bool, wrapAround: Bool, stdin: String?) throws(CmdFail) -> Workspace {
    let stdinWorkspaces: [WorkspaceName]
    switch stdin?.split(whereSeparator: \.isWhitespace)
        .map({ String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
        .filter({ !$0.isEmpty })
        .mapAllOrFailure(WorkspaceName.parse)
    {
        case .success(let names): stdinWorkspaces = names
        case .failure(let msg): throw CmdFail(msg)
        case nil: stdinWorkspaces = []
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
