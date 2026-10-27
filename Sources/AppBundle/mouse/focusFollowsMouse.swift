import AppKit

func syncFocusFollowsMouse(_ config: Config) { mouseMovedMonitor.sync(enabled: config.focusFollowsMouse.enabled) }

private let mouseMovedMonitor = FocusFollowsMouseMonitor()

/// The global mouse-moved monitor while focus-follows-mouse is enabled
private final class FocusFollowsMouseMonitor {
    private var monitor: Any? = nil

    func sync(enabled: Bool) {
        if enabled == (monitor != nil) { return }
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            world.sessions.cancelFocusFollowsMouse()
            return
        }
        checkIsAeroSpaceApp("focus-follows-mouse's global mouse monitor")
        // Interestingly, this callback seems to not fire when the mouse is down which is good,
        // because this is how I want it to work for windows/tabs/files dragging
        // swiftlint:disable:next live_effect
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { @MainActor event in
            world.sessions.onMouseMoved(to: event.locationInWindow.withYAxisFlipped)
        }
    }
}

/// The window under the mouse on the active workspace of the monitor there: the most recent floating window that contains
/// `location`, else the fullscreen window, else the tiling window there. nil over a menu bar dropdown
func window(underMouse location: CGPoint) async throws -> Window? {
    try checkCancellation()
    // Ignores macOS menubar dropdown, but, unfortunately, it doesn't ignore non-native menu-like fake windows.
    // todo: It would be cool to somehow reuse isWindowHeuristic logic here
    if await isAxWindowUnderMouse(location) == false { return nil }
    try checkCancellation()
    let workspace = world.monitors.approximation(location).activeWorkspace
    for child in workspace.existingContainer(.floating)?.mruChildren ?? [] {
        try checkCancellation()
        guard let child = child as? Window else { continue }
        if try await world.platform.observedRect(child.windowId)?.contains(location) == true { return child }
    }
    // A fullscreen window covers the whole workspace
    let root = workspace.existingRootTilingContainer
    return root?.mostRecentWindowRecursive.flatMap { $0.isFullscreen ? $0 : nil } ?? root?.window(at: location, virtual: false)
}

@concurrent
private nonisolated func isAxWindowUnderMouse(_ location: CGPoint) async -> Bool? {
    // Reached only through the guarded global monitor
    // swiftlint:disable:next live_effect
    let systemwide = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    if unsafe AXUIElementCopyElementAtPosition(systemwide, Float(location.x), Float(location.y), &element) != .success {
        return nil
    }
    guard let element else { return nil }
    return element.get(Ax.parentWindowRecursive) != nil || element.get(Ax.roleAttr) == kAXWindowRole
}
