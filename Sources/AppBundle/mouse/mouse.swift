import AppKit

nonisolated var isLeftMouseButtonDown: Bool { NSEvent.pressedMouseButtons == 1 }

/// Is the user moving or resizing `window` with the mouse right now
func isManipulatedWithMouse(_ window: Window) async -> Bool {
    guard !window.isHiddenInCorner, // Don't allow to resize/move windows of hidden workspaces
          isLeftMouseButtonDown,
          world.mouseManipulatedWindowId == nil || window.windowId == world.mouseManipulatedWindowId
    else { return false }
    // Only a cancelled session throws, and nothing cancels the AX event's task that awaits this
    return (try? await getNativeFocusedWindow(.cancellable)) == window
}

/// Same motivation as in monitorFrameNormalized
var mouseLocation: CGPoint { NSEvent.mouseLocation.withYAxisFlipped }
