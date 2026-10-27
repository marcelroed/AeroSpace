import AppKit

/// For the platform's AX threads (#1001). The model reads ``Platform/isLeftMouseDown``
nonisolated var isLeftMouseButtonDown: Bool { NSEvent.pressedMouseButtons == 1 }

/// Is the user moving or resizing `window` with the mouse right now
func isManipulatedWithMouse(_ window: Window) async -> Bool {
    guard !window.isHiddenInCorner, // Don't allow to resize/move windows of hidden workspaces
          world.platform.isLeftMouseDown,
          world.mouseManipulatedWindowId == nil || window.windowId == world.mouseManipulatedWindowId
    else { return false }
    // Only a cancelled session throws, and nothing cancels the AX event's task that awaits this
    return (try? await getNativeFocusedWindow()) == window
}
