import AppKit

func syncFocusFollowsMouse(_ config: Config) { focusFollowsMouse.sync(enabled: config.focusFollowsMouse.enabled) }

private let focusFollowsMouse = FocusFollowsMouseMonitor()

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

/// Focuses the window under the mouse. The task of ``Sessions/onMouseMoved(to:)``
func focusWindow(underMouse location: CGPoint) async throws {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    try checkCancellation()
    // Ignores macOS menubar dropdown, but, unfortunately, it doesn't ignore non-native menu-like fake windows.
    // todo: It would be cool to somehow reuse isWindowHeuristic logic here
    if await isAxWindowUnderMouse(location) == false { return }
    try checkCancellation()
    let workspace = world.monitors.approximation(location).activeWorkspace
    var window: Window? = nil
    for child in workspace.existingContainer(.floating)?.mruChildren ?? [] {
        try checkCancellation()
        guard let child = child as? Window else { continue }
        guard let rect = try await world.platform.observedRect(child.windowId) else { continue }
        if rect.contains(location) {
            window = child
            break
        }
    }
    if window == nil {
        // A fullscreen window covers the whole workspace
        let root = workspace.existingRootTilingContainer
        window = root?.mostRecentWindowRecursive.flatMap { $0.isFullscreen ? $0 : nil } ?? root?.window(at: location, virtual: false)
    }
    if let window {
        try await world.sessions.light(.focusFollowsMouse, token) {
            guard window.isAlive else { return } // The window closed at a suspension point
            _ = window.focusWindow()
            window.nativeFocus()
        }
    }
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
