import AppKit

/// Registers a new window where its kind goes (see ``unbindAndGetSlotForNewWindow(_:_:window:)``). At startup, on the
/// workspace of the monitor under the window's center, otherwise on the focused workspace. Sync, so the workspace is read
/// when the window is bound (RB-86). The closed-windows cache or on-window-detected may move it afterwards
func registerWindow(_ id: WindowId, _ app: AppInfo, _ detected: DetectedWindow, isStartup: Bool) -> Window {
    let workspace = if isStartup {
        (detected.rect.map { world.monitors.approximation($0.center) } ?? world.monitors.main).activeWorkspace
    } else {
        focus.workspace
    }
    let slot = unbindAndGetSlotForNewWindow(detected.kind, workspace, window: nil)
    return Window(id: id, app, parent: slot.parent, weight: nil, index: slot.index)
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

/// The detection of a new window: tells window-detected to the `subscribe` clients and runs the on-window-detected
/// callbacks, with `layout`'s layout for the next detected window around them. `run-callback` runs only the callbacks
func runOnWindowDetected(ifConventional window: Window, isStartup: Bool) async {
    guard window.shouldRunOnWindowDetected else { return }
    let layout = world.layoutForNextDetectedWindow
    world.layoutForNextDetectedWindow = nil
    func applyLayoutForNextDetectedWindow() async {
        if let layout {
            await Shell.cmd(LayoutCommand(toggleBetween: NonEmptyArray(layout)))
                .run(.defaultEnv.withWindowId(window.windowId), .emptyStdin)
        }
    }
    // The layout is applied both before and after the on-window-detected callbacks on purpose
    await applyLayoutForNextDetectedWindow()
    broadcastEvent(.windowDetected(
        windowId: window.windowId.raw,
        workspace: window.nodeWorkspace?.name,
        appBundleId: window.app.bundleId,
        appName: window.app.name,
    ))
    _ = await onWindowDetected(.defaultEnv, CmdIo.emptyStdinIgnoringOut, window, isStartup: isStartup)
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
