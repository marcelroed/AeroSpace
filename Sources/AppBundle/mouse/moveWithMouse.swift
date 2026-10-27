import AppKit
import Common

func moveWithMouse(_ window: Window) async throws { // todo cover with tests
    resetClosedWindowsCache()
    switch window.placement {
        case .floating: try await moveFloatingWindow(window)
        case .tiling: moveTilingWindow(window)
        case .macosFullscreen, .macosHiddenApp, .macosMinimized, .macosPopup, nil:
            return // Unconventional windows can't be moved with mouse
    }
}

private func moveFloatingWindow(_ window: Window) async throws {
    guard let center = try await window.getCenter(.cancellable) else { return }
    let targetWorkspace = world.monitors.approximation(center).activeWorkspace
    guard let workspace = window.nodeWorkspace else { return }
    if targetWorkspace != workspace {
        window.move(to: targetWorkspace.containerCreatingIfNeeded(.floating))
    }
}

private func moveTilingWindow(_ window: Window) {
    world.mouseManipulatedWindowId = window.windowId
    window.lastAppliedLayoutPhysicalRect = nil
    let mouseLocation = mouseLocation
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
    } else if let swapTarget {
        window.swap(with: swapTarget)
    }
}
