import AppKit
import Common

func moveWithMouse(_ window: Window) async throws {
    resetClosedWindowsCache()
    switch window.placement {
        case .floating: try await dragFloatingWindow(window)
        case .tiling: moveTilingWindow(window)
        case .macosFullscreen, .macosHiddenApp, .macosMinimized, .macosPopup, nil:
            return // Unconventional windows can't be moved with mouse
    }
}

/// A floating window changes workspace at the mouse up (``dropDraggedFloatingWindow()``), not mid-drag: the focus would go
/// with it to a monitor that the mouse may not be on yet, and `move-mouse monitor-lazy-center` in on-focused-monitor-changed
/// would warp the mouse while the user holds the button
private func dragFloatingWindow(_ window: Window) async throws {
    guard let center = try await world.platform.observedRect(window.windowId)?.center else { return }
    world.draggedFloatingWindow = (window.windowId, center)
    // The mouse up came during the read. This session presents the focus that the drop leaves: the window takes it at once
    if !world.platform.isLeftMouseDown { _ = dropDraggedFloatingWindow()?.focusWindow() }
}

/// The end of a floating window's drag: the window goes to the workspace of the monitor that its center is on, as a new
/// window does. Returns it if it moved there. AeroSpace's focus then falls to the workspace that it left, but macOS keeps
/// it on the window that the user held: the next session takes it from macOS (``syncFocusFromMacOs(_:)``). Not at once:
/// the mouse up's click detection would give the focus to the mouse's monitor, if the window isn't there
@discardableResult
func dropDraggedFloatingWindow() -> Window? {
    guard let drag = world.draggedFloatingWindow else { return nil }
    world.draggedFloatingWindow = nil
    // The window may have closed or stopped floating (e.g. `layout tiling`) during the drag. Don't make it floating again
    // (RB-87)
    guard let window = Window.get(byId: drag.id), case .floating(let workspace) = window.placement else { return nil }
    let target = world.monitors.approximation(drag.center).activeWorkspace
    if target == workspace { return nil }
    window.move(to: target.containerCreatingIfNeeded(.floating))
    world.focusStore.lastKnownNativeFocusedWindowId = nil
    return window
}

private func moveTilingWindow(_ window: Window) {
    world.mouseManipulatedWindowId = window.windowId
    window.lastAppliedLayoutPhysicalRect = nil
    let mouseLocation = world.platform.mouseLocation
    let targetWorkspace = world.monitors.approximation(mouseLocation).activeWorkspace
    let windowUnderMouse = targetWorkspace.existingRootTilingContainer?.window(at: mouseLocation, virtual: false)
    let swapTarget = windowUnderMouse == window ? nil : windowUnderMouse
    if targetWorkspace != window.nodeWorkspace { // Move window to a different monitor
        let index: Int = if let swapTarget, let (parent, index) = swapTarget.tilingSlot, let targetRect = swapTarget.lastAppliedLayoutPhysicalRect {
            mouseLocation.getProjection(parent.orientation) >= targetRect.center.getProjection(parent.orientation) ? index + 1 : index
        } else {
            0
        }
        window.move(to: swapTarget?.parent ?? targetWorkspace.rootTilingContainerCreatingIfNeeded(), at: index)
        _ = window.focusWindow() // The user holds it. Else the focus would stay on the workspace that it left
    } else if let swapTarget {
        window.swap(with: swapTarget)
    }
}
