import AppKit
import Common

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
