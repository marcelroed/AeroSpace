import AppKit

func syncFocusFollowsMouse(_ config: Config) { focusFollowsMouse.sync(enabled: config.focusFollowsMouse.enabled) }

private let focusFollowsMouse = FocusFollowsMouseMonitor()

/// The global mouse-moved monitor while focus-follows-mouse is enabled, and the focus change it started last
private final class FocusFollowsMouseMonitor {
    private var monitor: Any? = nil
    private let task = LatestTaskSlot()

    func sync(enabled: Bool) {
        if enabled == (monitor != nil) { return }
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            task.cancel()
            return
        }
        // Interestingly, this callback seems to not fire when the mouse is down which is good,
        // because this is how I want it to work for windows/tabs/files dragging
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { @MainActor [task] event in
            let location = event.locationInWindow.withYAxisFlipped
            task.replace { try await focusWindow(under: location) }
        }
    }
}

private func focusWindow(under location: CGPoint) async throws {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    try checkCancellation()
    // Ignores macOS menubar dropdown, but, unfortunately, it doesn't ignore non-native menu-like fake windows.
    // todo: It would be cool to somehow reuse isWindowHeuristic logic here
    if await isAxWindowUnderMouse(location) == false { return }
    try checkCancellation()
    let workspace = location.monitorApproximation.activeWorkspace
    var window: Window? = nil
    for child in workspace.floatingWindowsContainer.mruChildren {
        try checkCancellation()
        guard let child = child as? Window else { continue }
        guard let rect = try await child.getAxRect(.cancellable) else { continue }
        if rect.contains(location) {
            window = child
            break
        }
    }
    if window == nil {
        window = location.findWindowRecursively(in: workspace.rootTilingContainer, virtual: false, fullscreenCoversAll: true)
    }
    if let window {
        try await runLightSession(.focusFollowsMouse, token) {
            _ = window.focusWindow()
            window.nativeFocus()
        }
    }
}

@concurrent
private nonisolated func isAxWindowUnderMouse(_ location: CGPoint) async -> Bool? {
    let systemwide = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    if unsafe AXUIElementCopyElementAtPosition(systemwide, Float(location.x), Float(location.y), &element) != .success {
        return nil
    }
    guard let element else { return nil }
    return element.get(Ax.parentWindowRecursive) != nil || element.get(Ax.roleAttr) == kAXWindowRole
}
