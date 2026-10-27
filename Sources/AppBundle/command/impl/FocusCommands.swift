import AppKit
import Common

/// `focus` and `move` --boundaries
nonisolated enum Boundaries: String, CaseIterable, Equatable, Sendable {
    case workspace
    case allMonitorsOuterFrame = "all-monitors-outer-frame"
}

private let failIfFullscreenNeedsDirection: CmdParseError =
    "--fail-if-fullscreen/--fail-if-macos-native-fullscreen require using (left|down|up|right) argument"

struct FocusCommand: nonisolated Command {
    nonisolated enum Target: Equatable, Sendable {
        case direction(CardinalDirection)
        case dfsRelative(DfsNextPrev)
        case windowId(UInt32)
        case dfsIndex(UInt32)
    }

    nonisolated enum WhenBoundariesCrossed: String, CaseIterable, Equatable, Sendable {
        case stop = "stop"
        case fail = "fail"
        case wrapAroundTheWorkspace = "wrap-around-the-workspace"
        case wrapAroundAllMonitors = "wrap-around-all-monitors"
    }

    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var target: Target
    var boundaries: Boundaries = .workspace // todo cover boundaries wrapping with tests
    var boundariesAction: WhenBoundariesCrossed = .stop
    var floatingAsTiling = true
    var failIfFullscreen = false
    var failIfMacosNativeFullscreen = false

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var boundaries: Boundaries? = nil
        var boundariesAction: WhenBoundariesCrossed? = nil
        var wrapAround = false
        var floatingAsTiling = true
        var failIfFullscreen = false
        var failIfMacosNativeFullscreen = false
        var windowId: UInt32? = nil
        var dfsIndex: UInt32? = nil
        while let option = try a.nextOption() {
            switch option {
                case "--ignore-floating": floatingAsTiling = false
                case "--window-id": windowId = try a.windowId(of: option)
                case "--dfs-index": dfsIndex = try a.value(of: option, "<dfs-index>", parseUInt32)
                case "--boundaries": boundaries = try a.value(of: option, "<boundary>")
                case "--boundaries-action": boundariesAction = try a.value(of: option, "<action>")
                case "--fail-if-fullscreen": failIfFullscreen = true
                case "--fail-if-macos-native-fullscreen": failIfMacosNativeFullscreen = true
                case "--wrap-around": wrapAround = true
                default: throw .unknownOption(option)
            }
        }
        let direction: CardinalOrDfsDirection? = try a.positional()
        try a.end()
        if wrapAround && boundariesAction != nil { throw .conflicting("--wrap-around", "--boundaries-action") }
        if wrapAround && boundaries != nil { throw .conflicting("--wrap-around", "--boundaries") }
        let target: Target
        switch (direction, windowId, dfsIndex) {
            case (.direction(let direction), nil, nil): target = .direction(direction)
            case (.dfsRelative(let nextPrev), nil, nil): target = .dfsRelative(nextPrev)
            case (nil, let windowId?, nil): target = .windowId(windowId)
            case (nil, nil, let dfsIndex?): target = .dfsIndex(dfsIndex)
            case (nil, nil, nil):
                throw "Mandatory argument is missing. \(CardinalOrDfsDirection.unionLiteral), --window-id or --dfs-index is required"
            case (_, _?, _): throw "--window-id is incompatible with other options"
            case (_, nil, _?): throw "--dfs-index is incompatible with other options"
        }
        let result = Self(
            target: target,
            boundaries: boundaries ?? .workspace,
            boundariesAction: wrapAround ? .wrapAroundTheWorkspace : (boundariesAction ?? .stop),
            floatingAsTiling: floatingAsTiling,
            failIfFullscreen: failIfFullscreen,
            failIfMacosNativeFullscreen: failIfMacosNativeFullscreen,
        )
        if result.boundaries == .workspace && result.boundariesAction == .wrapAroundAllMonitors {
            throw "\(Boundaries.workspace.rawValue) and \(WhenBoundariesCrossed.wrapAroundAllMonitors.rawValue) is an invalid combination of values"
        }
        switch target {
            case .direction: break
            case .dfsRelative:
                if failIfFullscreen || failIfMacosNativeFullscreen { throw failIfFullscreenNeedsDirection }
                if result.boundaries != .workspace { throw "(dfs-next|dfs-prev) only supports --boundaries workspace" }
            case .windowId:
                if result != Self(target: target) { throw "--window-id is incompatible with other options" }
            case .dfsIndex:
                if result != Self(target: target) { throw "--dfs-index is incompatible with other options" }
        }
        return result
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let target: LiveFocus = if case .windowId(let windowId) = self.target {
            try cx.target(windowId: windowId)
        } else {
            try cx.target()
        }
        if let window = target.windowOrNil, await shouldFailBecauseFullscreen_nonCancellable(
            window: window,
            failIfFullscreen: failIfFullscreen,
            failIfMacosNativeFullscreen: failIfMacosNativeFullscreen,
        ) {
            throw .silent
        }
        // todo bug: floating windows break mru
        let floatingWindows = floatingAsTiling ? await makeFloatingWindowsSeenAsTiling(workspace: target.workspace) : []
        defer {
            if floatingAsTiling {
                restoreFloatingWindows(floatingWindows: floatingWindows, workspace: target.workspace)
            }
        }
        let windowToFocus: Window
        switch self.target {
            case .direction(let direction):
                let window = target.windowOrNil
                if let (parent, ownIndex) = window?.closestParent(hasChildrenInDirection: direction, withLayout: nil) {
                    guard let it = parent.children[ownIndex + direction.focusOffset]
                        .findLeafWindowRecursive(snappedTo: direction.opposite) else { throw CmdFail(bugPrompt()) }
                    windowToFocus = it
                } else {
                    return try hitWorkspaceBoundaries(target, direction)
                }
            case .windowId(let windowId):
                guard let it = Window.get(byId: windowId) else { throw "Can't find window with ID \(windowId)" }
                windowToFocus = it
            case .dfsIndex(let dfsIndex):
                guard let it = target.workspace.rootTilingContainer.allLeafWindowsRecursive.getOrNil(atIndex: Int(dfsIndex)) else {
                    throw "Can't find window with DFS index \(dfsIndex)"
                }
                windowToFocus = it
            case .dfsRelative(let nextPrev):
                let windows = target.workspace.rootTilingContainer.allLeafWindowsRecursive
                guard let window = target.windowOrNil else { throw CmdFail(noWindowIsFocused) }
                guard let currentIndex = windows.firstIndex(of: window) else {
                    throw "The window isn't part of the workspace tree" // E.g. a floating window with --ignore-floating
                }
                let targetIndex = currentIndex + nextPrev.indexOffset
                if let it = windows.getOrNil(atIndex: targetIndex) {
                    windowToFocus = it
                } else {
                    switch boundariesAction {
                        case .stop: return
                        case .fail: throw .silent
                        case .wrapAroundTheWorkspace: windowToFocus = windows.get(wrappingIndex: targetIndex).orDie()
                        case .wrapAroundAllMonitors: throw CmdFail(bugPrompt("Must be discarded by args parser"))
                    }
                }
        }
        if !windowToFocus.focusWindow() { throw .silent }
    }

    private func hitWorkspaceBoundaries(_ target: LiveFocus, _ direction: CardinalDirection) throws(CmdFail) {
        let wrappedMonitor: MonitorInfo?
        switch boundaries {
            case .workspace: wrappedMonitor = nil
            case .allMonitorsOuterFrame:
                guard let (monitors, index) = target.workspace.workspaceMonitor.findRelativeMonitor(inDirection: direction) else {
                    // No screens (e.g., during display reconfiguration): the monitor of the workspace is the fake mainMonitorInfo
                    if !hasScreens { throw CmdFail("Can't focus across monitors while there are no screens") }
                    throw CmdFail(bugPrompt("Should never happen. Can't find the current monitor"))
                }
                if let targetMonitor = monitors.getOrNil(atIndex: index) {
                    if !targetMonitor.activeWorkspace.focusWorkspace() { throw .silent }
                    return
                }
                guard let wrapped = monitors.get(wrappingIndex: index) else { throw CmdFail(bugPrompt("\(index) \(monitors)")) }
                wrappedMonitor = wrapped
        }
        switch boundariesAction {
            case .stop: return
            case .fail: throw .silent
            case .wrapAroundTheWorkspace:
                guard let windowToFocus = target.workspace.findLeafWindowRecursive(snappedTo: direction.opposite) else {
                    throw CmdFail(noWindowIsFocused)
                }
                if !windowToFocus.focusWindow() { throw .silent }
            case .wrapAroundAllMonitors:
                guard let wrappedMonitor else { throw CmdFail(bugPrompt("Must be discarded by args parser")) } // --boundaries workspace
                wrappedMonitor.activeWorkspace.findLeafWindowRecursive(snappedTo: direction.opposite)?.markAsMostRecentChild()
                if !wrappedMonitor.activeWorkspace.focusWorkspace() { throw .silent }
        }
    }
}

private func makeFloatingWindowsSeenAsTiling(workspace: Workspace) async -> [FloatingWindowData] {
    let mruBefore = workspace.mostRecentWindowRecursive
    defer {
        mruBefore?.markAsMostRecentChild()
    }
    var unsortedFloatingWindows: [FloatingWindowData] = []
    for window in workspace.floatingWindows {
        // todo bug: we shouldn't access ax api here. What if the window was moved but it wasn't committed to ax yet?
        guard let center = try? await window.getCenter(.nonCancellable) else { continue }

        let tilingParent: TilingContainer
        let index: Int
        if let target = center.coerce(in: workspace.workspaceMonitor.visibleRectPaddedByOuterGaps)?
            .findWindowRecursively(in: workspace.rootTilingContainer, virtual: true, fullscreenCoversAll: false)
        {
            guard let targetCenter = try? await target.getCenter(.nonCancellable) else { continue }
            guard let parent = target.parent as? TilingContainer else { continue }
            tilingParent = parent
            let isAfterTarget = center.getProjection(parent.orientation) >= targetCenter.getProjection(parent.orientation)
            index = switch parent.layout {
                case .tiles: target.ownIndex.orDie() + (isAfterTarget ? 1 : 0)
                case .accordion: isAfterTarget ? parent.children.count : 0
            }
        } else {
            index = 0
            tilingParent = workspace.rootTilingContainer
        }

        let data = window.unbindFromParent()
        let floatingWindowData = FloatingWindowData(
            window: window,
            center: center,
            tilingParent: tilingParent,
            weight: data.weight,
            index: index,
        )
        unsortedFloatingWindows.append(floatingWindowData)
    }
    let floatingWindows: [FloatingWindowData] = unsortedFloatingWindows.sortedBy { $0.center.getProjection($0.tilingParent.orientation) }.reversed()

    for floating in floatingWindows { // Make floating windows be seen as tiling
        floating.window.bind(to: floating.tilingParent, weight: 1, index: floating.index)
    }
    return floatingWindows
}

private func restoreFloatingWindows(floatingWindows: [FloatingWindowData], workspace: Workspace) {
    let mruBefore = workspace.mostRecentWindowRecursive
    defer {
        mruBefore?.markAsMostRecentChild()
    }
    for floating in floatingWindows {
        floating.window.bind(to: workspace.floatingWindowsContainer, weight: floating.weight)
    }
}

private struct FloatingWindowData {
    let window: Window
    let center: CGPoint

    let tilingParent: TilingContainer
    let weight: CGFloat
    let index: Int
}

extension TreeNode {
    func findLeafWindowRecursive(snappedTo direction: CardinalDirection) -> Window? {
        switch self {
            case let workspace as Workspace:
                return workspace.rootTilingContainer.findLeafWindowRecursive(snappedTo: direction)
            case let window as Window:
                return window
            case let container as TilingContainer:
                if direction.orientation == container.orientation {
                    return (direction.isPositive ? container.children.last : container.children.first)?
                        .findLeafWindowRecursive(snappedTo: direction)
                } else {
                    return mostRecentChild?.findLeafWindowRecursive(snappedTo: direction)
                }
            default:
                die("Impossible")
        }
    }
}

struct FocusBackAndForthCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        try a.noArgs()
        return Self()
    }

    func run(_ cx: CmdContext) throws(CmdFail) {
        guard let prevFocus else { throw "Prev window has been closed" }
        if !setFocus(to: prevFocus) { throw .silent }
    }
}

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
