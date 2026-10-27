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
        window.bindAsFloatingWindow(to: targetWorkspace)
    }
}

private func moveTilingWindow(_ window: Window) {
    currentlyManipulatedWithMouseWindowId = window.windowId
    window.lastAppliedLayoutPhysicalRect = nil
    let mouseLocation = mouseLocation
    let targetWorkspace = mouseLocation.monitorApproximation.activeWorkspace
    let windowUnderMouse = mouseLocation
        .findWindowRecursively(in: targetWorkspace.rootTilingContainer, virtual: false, fullscreenCoversAll: false)
    let swapTarget = windowUnderMouse == window ? nil : windowUnderMouse
    if targetWorkspace != window.nodeWorkspace { // Move window to a different monitor
        let index: Int = if let swapTarget, let parent = swapTarget.parent as? TilingContainer, let targetRect = swapTarget.lastAppliedLayoutPhysicalRect {
            mouseLocation.getProjection(parent.orientation) >= targetRect.center.getProjection(parent.orientation)
                ? swapTarget.ownIndex.orDie() + 1
                : swapTarget.ownIndex.orDie()
        } else {
            0
        }
        window.bind(
            to: swapTarget?.parent ?? targetWorkspace.rootTilingContainer,
            index: index,
        )
    } else if let swapTarget {
        swapWindows(mruDominant: window, swapTarget)
    }
}

func swapWindows(mruDominant window1: Window, _ window2: Window) {
    if window1 == window2 { return }

    let binding2 = window2.unbindFromParent()
    let binding1 = window1.unbindFromParent()

    window2.bind(to: binding1.parent, weight: binding1.weight, index: binding1.index)
    window1.bind(to: binding2.parent, weight: binding2.weight, index: binding2.index)
}

extension CGPoint {
    func findWindowRecursively(
        in tree: TilingContainer,
        virtual: Bool,
        fullscreenCoversAll: Bool,
    ) -> Window? {
        if fullscreenCoversAll {
            if let window = tree.mostRecentWindowRecursive, window.isFullscreen {
                return window
            }
        }
        return _findWindowRecursively(in: tree, virtual: virtual)
    }

    private func _findWindowRecursively(in tree: TilingContainer, virtual: Bool) -> Window? {
        let point = self
        let target: TreeNode? = switch tree.layout {
            case .tiles:
                tree.children.first(where: {
                    (virtual ? $0.lastAppliedLayoutVirtualRect : $0.lastAppliedLayoutPhysicalRect)?.contains(point) == true
                })
            case .accordion:
                tree.mostRecentChild
        }
        guard let target else { return nil }
        return switch target {
            case let window as Window: window
            case let container as TilingContainer: _findWindowRecursively(in: container, virtual: virtual)
            default: dieT("\(target.prettyDescription) can't be a child of a tiling container")
        }
    }
}
