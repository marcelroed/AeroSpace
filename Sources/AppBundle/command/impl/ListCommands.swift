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

/// A monitor of the `--monitor` filter of `list-workspaces` and `list-windows`
nonisolated enum MonitorId: Equatable, Sendable {
    case focused
    case all
    case mouse
    case index(Int)

    /// The values of `--monitor`
    static func parseList(_ raw: [String]) throws(CmdParseError) -> [Self] {
        let possibleValues = "<monitor> possible values: (<monitor-id>|focused|mouse|all)"
        if raw.isEmpty { throw "<monitor>... is mandatory. \(possibleValues)" }
        return try raw.map { (monitor) throws(CmdParseError) in
            if let index = Int(monitor) { return .index(index - 1) }
            switch monitor {
                case "mouse": return .mouse
                case "all": return .all
                case "focused": return .focused
                default: throw "Can't parse monitor ID '\(monitor)'. \(possibleValues)"
            }
        }
    }
}

struct ListWorkspacesCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    /// Not empty
    var onMonitors: [MonitorId]
    var visible: Bool? = nil
    var empty: Bool? = nil
    var output: ListOutput = .lines([.interVar(.workspace)])

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var all = false
        var focused = false
        var onMonitors: [MonitorId] = []
        var visible: Bool? = nil
        var empty: Bool? = nil
        var output = ListOutput.Options()
        while let option = try a.nextOption() {
            switch option {
                case "--all": all = true // Alias
                case "--focused": focused = true // Alias
                case "--visible": visible = a.noOrTrue()
                case "--empty": empty = a.noOrTrue()
                case "--monitor": onMonitors = try MonitorId.parseList(a.values())
                default: if try !output.take(option, &a, .workspace) { throw .unknownOption(option) }
            }
        }
        try a.end()
        try a.checkConflicts(["--all", "--focused", "--monitor"])
        let isFiltered = !onMonitors.isEmpty || visible != nil || empty != nil
        if !all && !focused && onMonitors.isEmpty { throw "Mandatory option is not specified (--all|--focused|--monitor)" }
        if all && isFiltered { throw "--all conflicts with any other \"filtering\" options" }
        if focused && isFiltered { throw "--focused conflicts with all other \"filtering\" options" }
        if all { onMonitors = [.all] }
        if focused {
            onMonitors = [.focused]
            visible = true
        }
        return Self(onMonitors: onMonitors, visible: visible, empty: empty, output: try output.build(defaultFormat: [.interVar(.workspace)]))
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        var result: [Workspace] = Workspace.all
        if let visible {
            result = result.filter { $0.isVisible == visible }
        }
        let monitors: Set<CGPoint> = try onMonitors.resolveMonitors()
        result = result.filter { monitors.contains($0.workspaceMonitor.rect.topLeftCorner) }
        if let empty {
            result = result.filter { $0.isEffectivelyEmpty == empty }
        }
        try output.print(result.map(AeroObj.workspace), cx)
    }
}

extension [MonitorId] {
    func resolveMonitors() throws(CmdFail) -> Set<CGPoint> {
        let sortedMonitors = sortedMonitorInfos
        var requested: Set<CGPoint> = []
        for id in self {
            let resolved = try id.resolve(sortedMonitors: sortedMonitors)
            if resolved.isEmpty { throw .silent }
            for monitor in resolved {
                requested.insert(monitor.rect.topLeftCorner)
            }
        }
        return requested
    }
}

extension MonitorId {
    func resolve(sortedMonitors: [MonitorInfo]) throws(CmdFail) -> [MonitorInfo] {
        switch self {
            case .focused: return [focus.workspace.workspaceMonitor]
            case .mouse: return [mouseLocation.monitorApproximation]
            case .all: return monitorInfos
            case .index(let index):
                guard let monitor = sortedMonitors.getOrNil(atIndex: index) else { throw "Invalid monitor ID: \(index + 1)" }
                return [monitor]
        }
    }
}

struct ListMonitorsCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var focused: Bool? = nil
    var mouse: Bool? = nil
    var output: ListOutput = .lines(defaultFormat)

    static let defaultFormat: [FormatToken] = [
        .interVar(.monitorId), .interVar(.rightPadding), .literal(" | "),
        .interVar(.monitorName),
    ]

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var result = Self()
        var output = ListOutput.Options()
        while let option = try a.nextOption() {
            switch option {
                case "--focused": result.focused = a.noOrTrue()
                case "--mouse": result.mouse = a.noOrTrue()
                default: if try !output.take(option, &a, .monitor) { throw .unknownOption(option) }
            }
        }
        try a.end()
        result.output = try output.build(defaultFormat: defaultFormat)
        return result
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let focus = focus
        var result = sortedMonitorInfos
        if let focused {
            result = result.filter { (monitor) in (monitor.activeWorkspace == focus.workspace) == focused }
        }
        if let mouse {
            let mouseWorkspace = mouseLocation.monitorApproximation.activeWorkspace
            result = result.filter { (monitor) in (monitor.activeWorkspace == mouseWorkspace) == mouse }
        }
        try output.print(result.map(AeroObj.monitor), cx)
    }
}

struct ListAppsCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var macosHidden: Bool? = nil
    var output: ListOutput = .lines(defaultFormat)

    static let defaultFormat: [FormatToken] = [
        .interVar(.appPid), .interVar(.rightPadding), .literal(" | "),
        .interVar(.appBundleId), .interVar(.rightPadding), .literal(" | "),
        .interVar(.appName),
    ]

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var result = Self()
        var output = ListOutput.Options()
        while let option = try a.nextOption() {
            switch option {
                case "--macos-native-hidden": result.macosHidden = a.noOrTrue()
                default: if try !output.take(option, &a, .app) { throw .unknownOption(option) }
            }
        }
        try a.end()
        result.output = try output.build(defaultFormat: defaultFormat)
        return result
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        var result = MacApp.allAppsMap.values.sorted { ($0.name ?? "", $0.pid) < ($1.name ?? "", $1.pid) }
        if let hidden = macosHidden {
            result = result.filter { $0.nsApp.isHidden == hidden }
        }
        try output.print(result.map(AeroObj.app), cx)
    }
}

struct ListModesCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var current = false
    var count = false
    var json = false

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var result = Self()
        while let option = try a.nextOption() {
            switch option {
                case "--count": result.count = true
                case "--current": result.current = true
                case "--json": result.json = true
                default: throw .unknownOption(option)
            }
        }
        try a.end()
        if result.count && result.current { throw .conflicting("--count", "--current") }
        if result.count && result.json { throw .conflicting("--count", "--json") }
        return result
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let modes: [String] = current ? [activeMode ?? mainModeId] : config.modes.keys.sorted()
        if count {
            cx.out("\(modes.count)")
        } else if json {
            guard let json = JSONEncoder.aeroSpaceDefault.encodeToString(modes.map { ["mode-id": $0] }) else {
                throw "Failed to encode JSON"
            }
            cx.out(json)
        } else {
            cx.out(modes)
        }
    }
}

struct ListExecEnvVarsCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        try a.noArgs()
        return Self()
    }

    func run(_ cx: CmdContext) {
        for (key, value) in config.execConfig.envVariables.sorted(by: { $0.key < $1.key }) {
            cx.out("\(key)=\(value)")
        }
    }
}
