import AppKit

/// The window that has the native focus, registered. Abandonable, see ``Platform/focusedWindow()``
func getNativeFocusedWindow() async throws(CancellationError) -> Window? {
    guard let focused = try await world.platform.focusedWindow() else { return nil }
    return try await registerWindow(focused.windowId, focused.app)
}
