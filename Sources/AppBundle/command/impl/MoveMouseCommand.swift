import AppKit
import Common

struct MoveMouseCommand: nonisolated Command {
    nonisolated enum MouseTarget: String, CaseIterable, Sendable {
        case monitorLazyCenter = "monitor-lazy-center"
        case monitorForceCenter = "monitor-force-center"
        case windowLazyCenter = "window-lazy-center"
        case windowForceCenter = "window-force-center"
    }

    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var mouseTarget: MouseTarget
    var failIfNoop = false

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var failIfNoop = false
        while let option = try a.nextOption() {
            switch option {
                case "--fail-if-noop": failIfNoop = true
                default: throw .unknownOption(option)
            }
        }
        let mouseTarget: MouseTarget = try parseEnum(a.positional("<mouse-position>"))
        try a.end()
        if failIfNoop && mouseTarget != .windowLazyCenter && mouseTarget != .monitorLazyCenter {
            throw "--fail-if-noop is only compatible with window-lazy-center or monitor-lazy-center"
        }
        return Self(mouseTarget: mouseTarget, failIfNoop: failIfNoop)
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let mouse = mouseLocation
        let target = try cx.target()
        switch mouseTarget {
            case .windowLazyCenter:
                let rect = try await windowSubjectRect(target)
                if rect.contains(mouse) {
                    return try noop(cx, failIfNoop: failIfNoop, "The mouse already belongs to the window. Tip: use --fail-if-noop to exit with non-zero code")
                }
                try moveMouse(rect.center)
            case .windowForceCenter:
                try await moveMouse(windowSubjectRect(target).center)
            case .monitorLazyCenter:
                let rect = target.workspace.workspaceMonitor.rect
                if rect.contains(mouse) {
                    return try noop(cx, failIfNoop: failIfNoop, "The mouse already belongs to the monitor. Tip: use --fail-if-noop to exit with non-zero code")
                }
                try moveMouse(rect.center)
            case .monitorForceCenter:
                try moveMouse(target.workspace.workspaceMonitor.rect.center)
        }
    }
}

private func moveMouse(_ point: CGPoint) throws(CmdFail) {
    guard let event = CGEvent(
        mouseEventSource: nil,
        mouseType: CGEventType.mouseMoved,
        mouseCursorPosition: point,
        mouseButton: CGMouseButton.left,
    ) else {
        throw "Failed to move mouse"
    }
    event.post(tap: CGEventTapLocation.cghidEventTap)
}

private func windowSubjectRect(_ target: LiveFocus) async throws(CmdFail) -> Rect {
    // todo bug it's bad that we operate on the "ax physical" state directly. command seq won't work correctly
    //      focus <direction> command has the similar problem
    guard let window = target.windowOrNil else { throw CmdFail(noWindowIsFocused) }
    if let rect = window.lastAppliedLayoutPhysicalRect { return rect }
    if let rect = try? await window.getAxRect(.nonCancellable) { return rect }
    throw "Failed to get rect of window '\(window.windowId)'"
}
