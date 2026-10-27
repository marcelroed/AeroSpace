import AppKit

var currentlyManipulatedWithMouseWindowId: UInt32? = nil
nonisolated var isLeftMouseButtonDown: Bool { NSEvent.pressedMouseButtons == 1 }

func isManipulatedWithMouse(_ window: Window) async throws -> Bool {
    guard !window.isHiddenInCorner, // Don't allow to resize/move windows of hidden workspaces
          isLeftMouseButtonDown,
          currentlyManipulatedWithMouseWindowId == nil || window.windowId == currentlyManipulatedWithMouseWindowId
    else { return false }
    return try await getNativeFocusedWindow(.cancellable) == window
}

/// The AX callback for the window moved/resized notifications. Runs on the AX thread
nonisolated func onMouseManipulationAxNotif(
    ax: AXUIElement,
    notif: CFString,
    _ task: LatestTaskSlot,
    _ manipulateWithMouse: @escaping @MainActor (Window) async throws -> (),
) {
    let windowId = ax.containingWindowId()
    let notif = notif as String
    Task.startUnstructured { @MainActor in
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        guard let windowId, let window = Window.get(byId: windowId), try await isManipulatedWithMouse(window) else {
            scheduleCancellableCompleteRefreshSession(.ax(notif))
            return
        }
        task.replace {
            try checkCancellation()
            try await runLightSession(.ax(notif), token) {
                try await manipulateWithMouse(window)
            }
        }
    }
}

/// Same motivation as in monitorFrameNormalized
var mouseLocation: CGPoint { NSEvent.mouseLocation.withYAxisFlipped }
