import AppKit
import Common

/// The monitor of `focus-monitor`, `move-node-to-monitor` and `move-workspace-to-monitor`
nonisolated enum MonitorTarget: Equatable, Sendable {
    case direction(CardinalDirection)
    case relative(NextPrev)
    case patterns([MonitorDescription])

    static let casesExceptPatterns = CardinalDirection.cliArgsCases + NextPrev.cliArgsCases
    static let placeholder = (casesExceptPatterns + ["<monitor-pattern>"]).joinedCliArgs

    /// A direction or `next`/`prev`, unless it comes after `--`. Otherwise all the positional args are patterns
    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        let (first, isLiteral) = try a.positionalAndIsLiteral(placeholder)
        if !isLiteral {
            if let nextPrev = NextPrev(rawValue: first) { return .relative(nextPrev) }
            if let direction = CardinalDirection(rawValue: first) { return .direction(direction) }
        }
        return try .patterns(([first] + a.allPositionals()).map { (raw) throws(CmdParseError) in
            switch parseMonitorDescription(raw) {
                case .success(let it): it
                case .failure(let msg): throw .invalid(msg)
            }
        })
    }

    var isPatterns: Bool {
        switch self {
            case .patterns: true
            default: false
        }
    }

    var directionOrNil: CardinalDirection? {
        switch self {
            case .direction(let direction): direction
            default: nil
        }
    }
}

struct FocusMonitorCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var target: MonitorTarget
    var wrapAround = false

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var wrapAround = false
        while let option = try a.nextOption() {
            switch option {
                case "--wrap-around": wrapAround = true
                default: throw .unknownOption(option)
            }
        }
        let target = try MonitorTarget.parse(&a)
        try a.end()
        if wrapAround && target.isPatterns { throw "--wrap-around is incompatible with <monitor-pattern> argument" }
        return Self(target: target, wrapAround: wrapAround)
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let targetMonitor = try target.resolve(cx.target().workspace.workspaceMonitor, wrapAround: wrapAround)
        if !targetMonitor.activeWorkspace.focusWorkspace() { throw .silent }
    }
}

extension MonitorTarget {
    func resolve(_ currentMonitor: MonitorInfo, wrapAround: Bool) throws(CmdFail) -> MonitorInfo {
        switch self {
            case .direction(let direction):
                guard let (monitorsInDirection, index) = currentMonitor.findRelativeMonitor(inDirection: direction) else {
                    // No screens (e.g., during display reconfiguration): currentMonitor is the fake mainMonitorInfo
                    if !hasScreens { throw CmdFail("Can't find monitors in direction \(direction) while there are no screens") }
                    throw CmdFail(bugPrompt("Should never happen. Can't find the current monitor"))
                }
                guard let monitor = wrapAround ? monitorsInDirection.get(wrappingIndex: index) : monitorsInDirection.getOrNil(atIndex: index) else {
                    throw "No monitors in direction \(direction)"
                }
                return monitor
            case .relative(let nextPrev):
                let monitors = sortedMonitorInfos
                guard let curIndex = monitors.firstIndex(where: { $0.rect.topLeftCorner == currentMonitor.rect.topLeftCorner }) else {
                    // No screens (e.g., during display reconfiguration): currentMonitor is the fake mainMonitorInfo
                    if !hasScreens { throw CmdFail("Can't find the \(nextPrev) monitor while there are no screens") }
                    throw CmdFail(bugPrompt("Should never happen. Can't find the current monitor"))
                }
                let targetIndex = nextPrev == .next ? curIndex + 1 : curIndex - 1
                guard let monitor = wrapAround ? monitors.get(wrappingIndex: targetIndex) : monitors.getOrNil(atIndex: targetIndex) else {
                    throw "Can't find target monitor"
                }
                return monitor
            case .patterns(let patterns):
                let monitors = sortedMonitorInfos
                guard let targetMonitor = patterns.lazy.compactMap({ $0.resolveMonitor(sortedMonitors: monitors) }).first else {
                    // No screens (e.g., during display reconfiguration): there are no monitors to match
                    if !hasScreens { throw CmdFail("Can't find monitors that match the pattern(s) while there are no screens") }
                    throw CmdFail("None of the monitors match the pattern(s)")
                }
                return targetMonitor
        }
    }
}

extension MonitorInfo {
    func relation(to monitor: MonitorInfo) -> Orientation {
        guard let otherYRange = monitor.rect.minY.until(excl: monitor.rect.maxY) else { return .h }
        guard let myYRange = rect.minY.until(excl: rect.maxY) else { return .h }
        return myYRange.overlaps(otherYRange) ? .h : .v
    }

    func findRelativeMonitor(inDirection direction: CardinalDirection) -> (monitorsInDirection: [MonitorInfo], index: Int)? {
        let currentMonitor = self
        let monitors = sortedMonitorInfos.filter {
            currentMonitor.rect.topLeftCorner == $0.rect.topLeftCorner ||
                $0.relation(to: currentMonitor) == direction.orientation
        }
        guard let index = monitors.firstIndex(where: { $0.rect.topLeftCorner == currentMonitor.rect.topLeftCorner }) else { return nil }
        return (monitors, index + direction.focusOffset)
    }
}
