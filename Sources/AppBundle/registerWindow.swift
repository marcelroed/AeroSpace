import AppKit

/// The window of `windowId`: registers it if it's new. A new window goes where its kind goes (see
/// ``unbindAndGetSlotForNewWindow(_:_:window:)``), then the closed-windows cache or on-window-detected place it
@discardableResult
func registerWindow(_ windowId: WindowId, _ app: AppInfo) async throws(CancellationError) -> Window {
    if let existing = Window.get(byId: windowId) { return existing }
    let detected = try await world.platform.classify([app: [windowId]])[windowId]
    let rect = detected?.rect
    let type = detected?.kind ?? .window
    // After the suspension points above: they can change the monitors and the focus
    let monitor = rect.map { world.monitors.approximation($0.center) } ?? world.monitors.main
    let workspace = isStartup ? monitor.activeWorkspace : focus.workspace
    let slot = unbindAndGetSlotForNewWindow(type, workspace, window: nil)

    // atomic synchronous section
    if let existing = Window.get(byId: windowId) { return existing }
    let window = Window(id: windowId, app, parent: slot.parent, weight: nil, index: slot.index)

    await debugWindowsIfRecording(window)
    if !restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: window) {
        await runOnWindowDetected(ifConventional: window)
    }
    return window
}

extension Window {
    /// Reads the window's kind, then moves the window to the slot of its kind on `workspace`
    func relayoutWindow(on workspace: Workspace) async {
        let kind: AxUiElementWindowType = await world.platform.kind(windowId) ?? .window
        // The window or the workspace may be gone after the suspension point above. The overload checks
        relayoutWindow(on: workspace, as: kind)
    }

    /// Moves the window to the slot of `kind` on `workspace`. A closed window or a gone workspace is left alone
    func relayoutWindow(on workspace: Workspace, as kind: AxUiElementWindowType) {
        guard isAlive, workspace.isAlive else { return }
        let slot = unbindAndGetSlotForNewWindow(kind, workspace, window: self)
        move(to: slot.parent, at: slot.index)
    }
}

/// Where a new window goes: index nil is the last one
private typealias NewWindowSlot = (parent: Container, index: Int?)

// The function is private because it's unsafe. A tiling slot leaves the window in unbound state
private func unbindAndGetSlotForNewWindow(_ type: AxUiElementWindowType, _ workspace: Workspace, window: Window?) -> NewWindowSlot {
    switch type {
        case .popup: return (macosPopupWindowsContainer, nil)
        case .dialog: return (workspace.containerCreatingIfNeeded(.floating), nil)
        case .window:
            window?.unbindFromParent() // See newTilingWindowSlot
            let slot = workspace.newTilingWindowSlot()
            return (slot.parent, slot.index)
    }
}

func runOnWindowDetected(ifConventional window: Window) async {
    guard window.shouldRunOnWindowDetected else { return }
    let layout = world.layoutForNextDetectedWindow
    world.layoutForNextDetectedWindow = nil
    func applyLayoutForNextDetectedWindow() async {
        if let layout {
            await LayoutCommand(toggleBetween: NonEmptyArray(layout))
                .run(.defaultEnv.withWindowId(window.windowId), .emptyStdin)
        }
    }
    // The layout is applied both before and after the on-window-detected callbacks on purpose
    await applyLayoutForNextDetectedWindow()
    _ = await onWindowDetected(.defaultEnv, CmdIo.emptyStdinIgnoringOut, window)
    await applyLayoutForNextDetectedWindow()
}

extension Window {
    /// on-window-detected callbacks skip popups and unbound windows
    var shouldRunOnWindowDetected: Bool {
        switch placement {
            case .tiling, .floating, .macosMinimized, .macosFullscreen, .macosHiddenApp: true
            case .macosPopup, nil: false
        }
    }
}
