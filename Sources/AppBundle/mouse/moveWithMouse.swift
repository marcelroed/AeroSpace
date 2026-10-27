import AppKit
import Common

nonisolated private let moveWithMouseTask = LatestTaskSlot()

/// AXObserver callback. Runs on the AX thread
nonisolated func movedObs(_: AXObserver, ax: AXUIElement, notif: CFString, _: UnsafeMutableRawPointer?) {
    onMouseManipulationAxNotif(ax: ax, notif: notif, moveWithMouseTask, moveWithMouse)
}

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
    guard let targetWorkspace = try await window.getCenter(.cancellable)?.monitorApproximation.activeWorkspace else { return }
    guard let workspace = window.nodeWorkspace else { return }
    if targetWorkspace != workspace {
        window.move(to: targetWorkspace.floatingWindowsContainer)
    }
}

private func moveTilingWindow(_ window: Window) {
    world.mouseManipulatedWindowId = window.windowId
    window.lastAppliedLayoutPhysicalRect = nil
    let mouseLocation = mouseLocation
    let targetWorkspace = mouseLocation.monitorApproximation.activeWorkspace
    let windowUnderMouse = targetWorkspace.rootTilingContainer.window(at: mouseLocation, virtual: false)
    let swapTarget = windowUnderMouse == window ? nil : windowUnderMouse
    if targetWorkspace != window.nodeWorkspace { // Move window to a different monitor
        let index: Int = if let swapTarget, let (parent, index) = swapTarget.tilingSlot, let targetRect = swapTarget.lastAppliedLayoutPhysicalRect {
            mouseLocation.getProjection(parent.orientation) >= targetRect.center.getProjection(parent.orientation) ? index + 1 : index
        } else {
            0
        }
        window.move(to: swapTarget?.parent ?? targetWorkspace.rootTilingContainer, at: index)
    } else if let swapTarget {
        window.swap(with: swapTarget)
    }
}
