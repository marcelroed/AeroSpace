import AppKit
import Common

struct ListWindowsCommand: nonisolated Command {
    nonisolated enum WorkspaceFilter: Equatable, Sendable {
        case focused
        case visible
        case name(WorkspaceName)
    }

    nonisolated struct FilteringOptions: Equatable, Sendable {
        var monitors: [MonitorId] = []
        var focused: Bool = false
        var workspaces: [WorkspaceFilter] = []
        var pidFilter: Int32? = nil
        var appIdFilter: String? = nil
    }

    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var filteringOptions: FilteringOptions
    var output: ListOutput = .lines(defaultFormat)

    static let defaultFormat: [FormatToken] = [
        .interVar(.windowId), .interVar(.rightPadding), .literal(" | "),
        .interVar(.appName), .interVar(.rightPadding), .literal(" | "),
        .interVar(.windowTitle),
    ]

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var all = false
        var filter = FilteringOptions()
        var output = ListOutput.Options()
        while let option = try a.nextOption() {
            switch option {
                case "--all": all = true
                case "--focused": filter.focused = true
                case "--monitor": filter.monitors = try MonitorId.parseList(a.values())
                case "--workspace": filter.workspaces = try parseWorkspaceFilters(a.values())
                case "--pid": filter.pidFilter = try a.value(of: option, "<pid>", parseInt32)
                case "--app-bundle-id": filter.appIdFilter = try a.value(of: option, "<app-bundle-id>")
                default: if try !output.take(option, &a, .window) { throw .unknownOption(option) }
            }
        }
        try a.end()
        try a.checkConflicts(["--all", "--focused", "--workspace"], ["--all", "--focused", "--monitor"])
        if !filter.focused && !all && filter.monitors.isEmpty && filter.workspaces.isEmpty {
            throw "Mandatory option is not specified (--focused|--all|--monitor|--workspace)"
        }
        if all && filter != FilteringOptions() {
            throw "--all conflicts with \"filtering\" flags. Please use '--monitor all' instead of '--all' alias"
        }
        if filter.focused {
            var others = filter
            others.focused = false
            if others != FilteringOptions() { throw "--focused conflicts with other \"filtering\" flags" }
        }
        if all { filter.monitors = [.all] } // Normalize the alias
        return Self(filteringOptions: filter, output: try output.build(defaultFormat: defaultFormat))
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let focus = focus
        var windows: [Window] = []
        if filteringOptions.focused {
            guard let window = focus.windowOrNil else { throw CmdFail(noWindowIsFocused) }
            windows = [window]
        } else {
            var workspaces: Set<Workspace> = filteringOptions.workspaces.isEmpty
                ? Workspace.all.toSet()
                : filteringOptions.workspaces
                    .flatMap { filter in
                        switch filter {
                            case .focused: [focus.workspace]
                            case .visible: Workspace.all.filter(\.isVisible)
                            case .name(let name): [Workspace.get(byName: name.raw)]
                        }
                    }
                    .toSet()
            if !filteringOptions.monitors.isEmpty {
                let monitors: Set<CGPoint> = try filteringOptions.monitors.resolveMonitors()
                workspaces = workspaces.filter { monitors.contains($0.workspaceMonitor.rect.topLeftCorner) }
            }
            // A Set iterates in a random order. Windows that tie in the final sort keep workspace order, then tree order
            windows = workspaces.sorted().flatMap(\.allLeafWindowsRecursive)
            if let pid = filteringOptions.pidFilter {
                windows = windows.filter { $0.app.pid == pid }
            }
            if let appId = filteringOptions.appIdFilter {
                windows = windows.filter { $0.app.rawAppBundleId == appId }
            }
        }
        if case .count = output {
            cx.out("\(windows.count)")
            return
        }
        var resolved: [WindowWithPrefetchedTitle] = []
        for window in windows {
            guard let window = try? await WindowWithPrefetchedTitle.resolveWindow(window, for: output.format, .nonCancellable) else {
                throw CmdFail(bugPrompt())
            }
            resolved.append(window)
        }
        let list = resolved
            .filter { $0.window.isBound }
            .sortedBy([{ $0.window.app.name ?? "" }, { $0.title ?? "" }])
            .map(AeroObj.window)
        try output.print(list, cx)
    }
}

private func parseWorkspaceFilters(_ raw: [String]) throws(CmdParseError) -> [ListWindowsCommand.WorkspaceFilter] {
    if raw.isEmpty { throw "<workspace>... is mandatory. <workspace> possible values: (<workspace-name>|focused|visible)" }
    return try raw.map { (workspace) throws(CmdParseError) in
        switch workspace {
            case "visible": .visible
            case "focused": .focused
            default: .name(try parseWorkspaceName(workspace))
        }
    }
}
