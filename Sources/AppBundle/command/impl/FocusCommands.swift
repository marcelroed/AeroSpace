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
    /// Each target carries the options that apply to it
    nonisolated enum Target: Equatable, Sendable {
        case direction(CardinalDirection, DirectionOptions = DirectionOptions())
        case dfsRelative(DfsNextPrev, atEdge: AtEdge = .stop, floatingAsTiling: Bool = true)
        case windowId(UInt32)
        case dfsIndex(UInt32)
    }

    nonisolated struct DirectionOptions: Equatable, Sendable {
        var boundaries: DirectionBoundaries = .workspace(.stop) // todo cover boundaries wrapping with tests
        var floatingAsTiling = true
        var failIfFullscreen = false
        var failIfMacosNativeFullscreen = false
    }

    /// `--boundaries` and `--boundaries-action` of `focus <direction>`
    nonisolated enum DirectionBoundaries: Equatable, Sendable {
        /// `--boundaries workspace`
        case workspace(AtEdge)
        /// `--boundaries all-monitors-outer-frame`: focus crosses to the monitor in the direction. `AtEdge` applies at the
        /// outer frame of all monitors
        case allMonitorsOuterFrame(AtEdge)
        /// `... --boundaries-action wrap-around-all-monitors`: at the outer frame, focus crosses to the monitor at the other end
        case allMonitorsWrappingAround
    }

    /// What focus does at the edge of the workspace (or of all monitors) when there's no window beyond it
    nonisolated enum AtEdge: Equatable, Sendable {
        case stop, fail, wrapAroundTheWorkspace
    }

    /// The values of `--boundaries-action`
    nonisolated enum WhenBoundariesCrossed: String, CaseIterable, Equatable, Sendable {
        case stop = "stop"
        case fail = "fail"
        case wrapAroundTheWorkspace = "wrap-around-the-workspace"
        case wrapAroundAllMonitors = "wrap-around-all-monitors"
    }

    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var target: Target

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var options = DirectionOptions()
        var boundaries: Boundaries? = nil
        var boundariesAction: WhenBoundariesCrossed? = nil
        var wrapAround = false
        var windowId: UInt32? = nil
        var dfsIndex: UInt32? = nil
        var hasOtherOptions = false
        while let option = try a.nextOption() {
            hasOtherOptions = hasOtherOptions || (option != "--window-id" && option != "--dfs-index")
            switch option {
                case "--ignore-floating": options.floatingAsTiling = false
                case "--window-id": windowId = try a.windowId(of: option)
                case "--dfs-index": dfsIndex = try a.value(of: option, "<dfs-index>", parseUInt32)
                case "--boundaries": boundaries = try a.value(of: option, "<boundary>")
                case "--boundaries-action": boundariesAction = try a.value(of: option, "<action>")
                case "--fail-if-fullscreen": options.failIfFullscreen = true
                case "--fail-if-macos-native-fullscreen": options.failIfMacosNativeFullscreen = true
                case "--wrap-around": wrapAround = true
                default: throw .unknownOption(option)
            }
        }
        let direction: CardinalOrDfsDirection? = try a.positional()
        try a.end()
        if wrapAround && boundariesAction != nil { throw .conflicting("--wrap-around", "--boundaries-action") }
        if wrapAround && boundaries != nil { throw .conflicting("--wrap-around", "--boundaries") }
        switch (direction, windowId, dfsIndex) { // The target's errors come before the boundaries' errors
            case (nil, nil, nil):
                throw "Mandatory argument is missing. \(CardinalOrDfsDirection.unionLiteral), --window-id or --dfs-index is required"
            case (_?, _?, _), (_, _?, _?): throw "--window-id is incompatible with other options"
            case (_?, nil, _?): throw "--dfs-index is incompatible with other options"
            default: break
        }
        let atEdge: AtEdge? = switch wrapAround ? .wrapAroundTheWorkspace : boundariesAction ?? .stop {
            case .stop: .stop
            case .fail: .fail
            case .wrapAroundTheWorkspace: .wrapAroundTheWorkspace
            case .wrapAroundAllMonitors: nil
        }
        options.boundaries = switch (boundaries ?? .workspace, atEdge) {
            case (.workspace, let atEdge?): .workspace(atEdge)
            case (.allMonitorsOuterFrame, let atEdge?): .allMonitorsOuterFrame(atEdge)
            case (.allMonitorsOuterFrame, nil): .allMonitorsWrappingAround
            case (.workspace, nil):
                throw "\(Boundaries.workspace.rawValue) and \(WhenBoundariesCrossed.wrapAroundAllMonitors.rawValue) is an invalid combination of values"
        }
        let target: Target
        switch (direction, windowId, dfsIndex) {
            case (.direction(let direction), _, _): target = .direction(direction, options)
            case (.dfsRelative(let nextPrev), _, _):
                if options.failIfFullscreen || options.failIfMacosNativeFullscreen { throw failIfFullscreenNeedsDirection }
                guard case .workspace(let atEdge) = options.boundaries else { throw "(dfs-next|dfs-prev) only supports --boundaries workspace" }
                target = .dfsRelative(nextPrev, atEdge: atEdge, floatingAsTiling: options.floatingAsTiling)
            case (nil, let windowId?, _) where !hasOtherOptions: target = .windowId(windowId)
            case (nil, _?, _): throw "--window-id is incompatible with other options"
            case (nil, nil, let dfsIndex?) where !hasOtherOptions: target = .dfsIndex(dfsIndex)
            case (nil, nil, _): throw "--dfs-index is incompatible with other options"
        }
        return Self(target: target)
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let target: LiveFocus = if case .windowId(let windowId) = self.target {
            try cx.target(windowId: windowId)
        } else {
            try cx.target()
        }
        if case .direction(_, let options) = self.target, let window = target.windowOrNil {
            try await window.failIfFullscreen(options.failIfFullscreen, macosNativeFullscreen: options.failIfMacosNativeFullscreen)
        }
        let floatingAsTiling = switch self.target {
            case .direction(_, let options): options.floatingAsTiling
            case .dfsRelative(_, _, let floatingAsTiling): floatingAsTiling
            case .dfsIndex: true
            case .windowId: false // Doesn't look at the tree
        }
        let floatingWindows = floatingAsTiling ? await floatingWindowCenters(target.workspace) : []
        // Focus sees the floating windows as tiling windows only while it decides. Then the tree is as before: order and MRU
        let change = try world.withTemporaryTreeEdits { () throws(CmdFail) -> FocusChange? in
            bindAsTiling(floatingWindows, target.workspace)
            return try findChange(target)
        }
        switch change {
            case nil: return
            case .window(let window):
                if !window.focusWindow() { throw .silent }
            case .workspace(let workspace, let mostRecent):
                mostRecent?.markAsMostRecentChild()
                if !workspace.focusWorkspace() { throw .silent }
        }
    }

    private func findChange(_ target: LiveFocus) throws(CmdFail) -> FocusChange? {
        switch self.target {
            case .direction(let direction, let options):
                guard let neighbor = target.windowOrNil?.neighbor(direction) else {
                    return try atWorkspaceEdge(target.workspace, direction, options.boundaries)
                }
                guard let window = neighbor.edgeWindow(snappedTo: direction.opposite) else { throw CmdFail(bugPrompt()) }
                return .window(window)
            case .windowId:
                return target.windowOrNil.map { .window($0) }
            case .dfsIndex(let dfsIndex):
                guard let window = target.workspace.tilingWindows.getOrNil(atIndex: Int(dfsIndex)) else {
                    throw "Can't find window with DFS index \(dfsIndex)"
                }
                return .window(window)
            case .dfsRelative(let nextPrev, let atEdge, _):
                guard let window = target.windowOrNil else { throw CmdFail(noWindowIsFocused) }
                let wrapAround = atEdge == .wrapAroundTheWorkspace
                if let next = try target.workspace.dfsNeighbor(of: window, nextPrev, wrapAround: wrapAround) { return .window(next) }
                if atEdge == .fail { throw .silent }
                return nil
        }
    }

    private func atWorkspaceEdge(_ workspace: Workspace, _ direction: CardinalDirection, _ boundaries: DirectionBoundaries) throws(CmdFail) -> FocusChange? {
        let atEdge: AtEdge
        switch boundaries {
            case .workspace(let it):
                atEdge = it
            case .allMonitorsOuterFrame(let it):
                let (monitor, wrapped) = try workspace.workspaceMonitor.monitor(in: direction)
                if !wrapped { return .workspace(monitor.activeWorkspace) }
                atEdge = it
            case .allMonitorsWrappingAround:
                let (monitor, wrapped) = try workspace.workspaceMonitor.monitor(in: direction)
                let edgeWindow = wrapped ? monitor.activeWorkspace.edgeWindow(snappedTo: direction.opposite) : nil
                return .workspace(monitor.activeWorkspace, mostRecent: edgeWindow)
        }
        switch atEdge {
            case .stop: return nil
            case .fail: throw .silent
            case .wrapAroundTheWorkspace:
                guard let window = workspace.edgeWindow(snappedTo: direction.opposite) else { throw CmdFail(noWindowIsFocused) }
                return .window(window)
        }
    }
}

/// What focus focuses, once the tree is back as it was
private enum FocusChange {
    case window(Window)
    /// The workspace focuses its most recent window. `mostRecent` becomes that window first
    case workspace(Workspace, mostRecent: Window? = nil)
}

extension Workspace {
    /// The tiling window after or before `window` in DFS order. nil past the ends, unless `wrapAround`
    func dfsNeighbor(of window: Window, _ nextPrev: DfsNextPrev, wrapAround: Bool) throws(CmdFail) -> Window? {
        let windows = tilingWindows
        guard let index = windows.firstIndex(of: window) else {
            throw "The window isn't part of the workspace tree" // E.g. a floating window with --ignore-floating
        }
        let next = index + nextPrev.indexOffset
        return wrapAround ? windows.get(wrappingIndex: next) : windows.getOrNil(atIndex: next)
    }
}

/// A floating window and the tiling window under its center, with their centers as AX reports them
private struct FloatingWindowCenter {
    let window: Window
    let center: CGPoint
    let tilingWindowUnderCenter: (window: Window, center: CGPoint)?
}

/// Where the floating windows of `workspace` are. AX reads, so they happen before focus edits the tree
private func floatingWindowCenters(_ workspace: Workspace) async -> [FloatingWindowCenter] {
    var result: [FloatingWindowCenter] = []
    for window in workspace.floatingWindows {
        // todo bug: we shouldn't access ax api here. What if the window was moved but it wasn't committed to ax yet?
        guard let center = try? await window.getCenter(.nonCancellable) else { continue }
        let root = workspace.existingRootTilingContainer
        guard let tilingWindow = center.coerce(in: workspace.workspaceMonitor.visibleRectPaddedByOuterGaps)
            .flatMap({ root?.window(at: $0, virtual: true) })
        else {
            result.append(FloatingWindowCenter(window: window, center: center, tilingWindowUnderCenter: nil))
            continue
        }
        guard let tilingCenter = try? await tilingWindow.getCenter(.nonCancellable) else { continue }
        result.append(FloatingWindowCenter(window: window, center: center, tilingWindowUnderCenter: (tilingWindow, tilingCenter)))
    }
    return result
}

/// Puts each floating window into the tiling tree, before or after the tiling window under its center (by their centers),
/// so that focus sees the floating windows as tiling windows. The most recent window stays the most recent one
private func bindAsTiling(_ floatingWindows: [FloatingWindowCenter], _ workspace: Workspace) {
    typealias Slot = (window: Window, center: CGPoint, parent: TilingContainer, index: Int)
    let slots: [Slot] = floatingWindows.compactMap { (floating: FloatingWindowCenter) -> Slot? in
        // The tree may have changed during the AX reads
        guard floating.window.parent == workspace.floatingWindowsContainer else { return nil }
        guard let (tilingWindow, tilingCenter) = floating.tilingWindowUnderCenter else {
            return (floating.window, floating.center, workspace.rootTilingContainer, 0)
        }
        guard let (parent, index) = tilingWindow.tilingSlot, tilingWindow.nodeWorkspace == workspace else { return nil }
        let isAfter = floating.center.getProjection(parent.orientation) >= tilingCenter.getProjection(parent.orientation)
        let slotIndex: Int = switch parent.layout {
            case .tiles: index + (isAfter ? 1 : 0)
            case .accordion: isAfter ? parent.children.count : 0
        }
        return (floating.window, floating.center, parent, slotIndex)
    }
    let mostRecentBefore = workspace.mostRecentWindowRecursive
    for slot in slots.sortedBy({ $0.center.getProjection($0.parent.orientation) }).reversed() {
        slot.window.move(to: slot.parent, at: slot.index, weight: .value(1))
    }
    mostRecentBefore?.markAsMostRecentChild()
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
        return try .patterns(([first] + a.allPositionals()).map(parseMonitorDescription))
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
                let (monitor, wrapped) = try currentMonitor.monitor(in: direction)
                if wrapped && !wrapAround { throw "No monitors in direction \(direction)" }
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

    /// The monitor next to this one in `direction`. If there is none, `wrapped` is true, and the monitor is the one at the
    /// far end on the other side (or this one)
    func monitor(in direction: CardinalDirection) throws(CmdFail) -> (monitor: MonitorInfo, wrapped: Bool) {
        let monitors = sortedMonitorInfos.filter { rect.topLeftCorner == $0.rect.topLeftCorner || $0.relation(to: self) == direction.orientation }
        guard let index = monitors.firstIndex(where: { $0.rect.topLeftCorner == rect.topLeftCorner }) else {
            // No screens (e.g., during display reconfiguration): this monitor is the fake mainMonitorInfo
            if !hasScreens { throw "Can't find monitors in direction \(direction) while there are no screens" }
            throw CmdFail(bugPrompt("Should never happen. Can't find the current monitor"))
        }
        let next = index + direction.focusOffset
        if let monitor = monitors.getOrNil(atIndex: next) { return (monitor, false) }
        return (monitors.get(wrappingIndex: next).orDie(), true)
    }
}
