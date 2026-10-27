import AppKit
import Common

struct MoveNodeToMonitorCommand: nonisolated Command {
    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var target: MonitorTarget
    var wrapAround = false
    var focusFollowsWindow = false
    var failIfNoop = false
    var windowId: UInt32? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var wrapAround = false
        var focusFollowsWindow = false
        var failIfNoop = false
        var windowId: UInt32? = nil
        while let option = try a.nextOption() {
            switch option {
                case "--wrap-around": wrapAround = true
                case "--focus-follows-window": focusFollowsWindow = true
                case "--fail-if-noop": failIfNoop = true
                case "--window-id": windowId = try a.windowId(of: option)
                default: throw .unknownOption(option)
            }
        }
        let target = try MonitorTarget.parse(&a)
        try a.end()
        if wrapAround && target.isPatterns { throw "--wrap-around is incompatible with <monitor-pattern> argument" }
        if failIfNoop && !target.isPatterns { throw "--fail-if-noop is incompatible with \(MonitorTarget.casesExceptPatterns.joinedCliArgs)" }
        return Self(target: target, wrapAround: wrapAround, focusFollowsWindow: focusFollowsWindow, failIfNoop: failIfNoop, windowId: windowId)
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let window = try cx.window(windowId: windowId)
        guard let currentMonitor = window.nodeMonitor else { throw CmdFail(windowIsntPartOfTree(window)) }
        let targetMonitor = try target.resolve(currentMonitor, wrapAround: wrapAround)
        let targetWs = targetMonitor.activeWorkspace
        let index = true == target.directionOrNil
            .map { dir in dir.isPositive && targetWs.rootTilingContainer.orientation == dir.orientation }
            ? 0
            : nil
        try moveWindowToWorkspace(window, targetWs, cx, focusFollowsWindow: focusFollowsWindow, failIfNoop: failIfNoop, index: index)
    }
}

func windowIsntPartOfTree(_ window: Window) -> String {
    "Window \(window.windowId) is not part of tree (minimized or hidden)"
}
