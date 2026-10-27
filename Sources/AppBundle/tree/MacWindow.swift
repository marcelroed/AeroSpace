import AppKit
import Common

final class MacWindow: Window {
    let macApp: MacApp
    private var prevUnhiddenProportionalPositionInsideWorkspaceRect: CGPoint?

    private init(_ id: UInt32, _ macApp: MacApp, lastFloatingSize: CGSize?, parent: Container, index: Int?) {
        self.macApp = macApp
        super.init(id: id, macApp, lastFloatingSize: lastFloatingSize, parent: parent, weight: nil, index: index)
    }

    static var allWindowsMap: [UInt32: MacWindow] = [:]
    static var allWindows: [MacWindow] { Array(allWindowsMap.values) }

    @discardableResult
    static func getOrRegister(windowId: UInt32, macApp: MacApp) async throws -> MacWindow {
        if let existing = allWindowsMap[windowId] { return existing }
        let rect = try await macApp.getAxRect(windowId, .cancellable)
        let workspace = isStartup ? (rect?.center.monitorApproximation ?? mainMonitorInfo).activeWorkspace : focus.workspace
        let type = try await macApp.getAxUiElementWindowType(windowId, getWindowLevel(for: windowId), .cancellable)
        let slot = unbindAndGetSlotForNewWindow(type, workspace, window: nil)

        // atomic synchronous section
        if let existing = allWindowsMap[windowId] { return existing }
        let window = MacWindow(windowId, macApp, lastFloatingSize: rect?.size, parent: slot.parent, index: slot.index)
        allWindowsMap[windowId] = window

        try await debugWindowsIfRecording(window, .cancellable)
        if try await !restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: window) {
            await runOnWindowDetected(ifConventional: window)
        }
        return window
    }

    func setNativeFullscreen(_ value: Bool) {
        macApp.setAxAttr(windowId, Ax.isFullscreenAttr, value)
    }

    func setNativeMinimized(_ value: Bool) {
        macApp.setAxAttr(windowId, Ax.minimizedAttr, value)
    }

    // skipClosedWindowsCache is an optimization when it's definitely not necessary to cache closed window.
    //                        If you are unsure, it's better to pass `false`
    func garbageCollect(skipClosedWindowsCache: Bool) {
        if MacWindow.allWindowsMap.removeValue(forKey: windowId) == nil {
            return
        }
        if !skipClosedWindowsCache { cacheClosedWindowIfNeeded() }
        guard let parent = destroy()?.parent else { return }
        let deadWindowWorkspace = parent.nodeWorkspace
        let focus = focus
        if let deadWindowWorkspace, deadWindowWorkspace == focus.workspace ||
            deadWindowWorkspace == prevFocusedWorkspace && world.focusStore.prevWorkspaceDate.distance(to: .now) < 1
        {
            switch (parent as? Container)?.kind {
                case .tiling, .floating, .macosHiddenApp, .macosFullscreen:
                    let deadWindowFocus = deadWindowWorkspace.toLiveFocus()
                    _ = setFocus(to: deadWindowFocus)
                    // Guard against "Apple Reminders popup" bug: https://github.com/nikitabobko/AeroSpace/issues/201
                    if focus.windowOrNil?.app.pid != app.pid {
                        // Force focus to fix macOS annoyance with focused apps without windows.
                        //   https://github.com/nikitabobko/AeroSpace/issues/65
                        deadWindowFocus.windowOrNil?.nativeFocus()
                    }
                case .macosPopup, // Don't switch back on popup destruction
                     .macosMinimized, // Don't switch back on minimized windows destruction
                     nil: // A window's parent is always a container
                    break
            }
        }
    }

    override func getTitle(_ cm: CancellationMode) async throws -> String { try await macApp.getAxAttr(windowId, Ax.titleAttr, cm) ?? "" }
    override func isMacosFullscreen(_ cm: CancellationMode) async throws -> Bool { try await macApp.getAxAttr(windowId, Ax.isFullscreenAttr, cm) == true }
    override func isMacosMinimized(_ cm: CancellationMode) async throws -> Bool { try await macApp.getAxAttr(windowId, Ax.minimizedAttr, cm) == true }
    override func getMacosFullscreenAndMinimized(_ cm: CancellationMode) async throws -> (isFullscreen: Bool, isMinimized: Bool) {
        try await macApp.getMacosFullscreenAndMinimized(windowId, cm) ?? (false, false)
    }

    override func nativeFocus() {
        macApp.nativeFocus(windowId)
    }

    override func closeAxWindow() {
        garbageCollect(skipClosedWindowsCache: true)
        macApp.closeAndUnregisterAxWindow(windowId)
    }

    // todo it's part of the window layout and should be moved to layout.swift
    func hideInCorner(_ corner: OptimalHideCorner) async throws {
        guard let nodeMonitor else { return }
        // Don't accidentally override prevUnhiddenProportionalPositionInsideWorkspaceRect in case of subsequent `hideInCorner` calls
        if !isHiddenInCorner {
            guard let windowRect = try await getAxRect(.cancellable) else { return }
            // The screens may disappear at the suspension point above. Don't remember the position relative to the fake
            // mainMonitorInfo, the window would come back at the wrong place
            if !hasScreens { return }
            // Check for isHiddenInCorner for the second time because of the suspension point above
            if !isHiddenInCorner {
                let topLeftCorner = windowRect.topLeftCorner
                let monitorRect = windowRect.center.monitorApproximation.rect // Similar to layoutFloatingWindows. Non idempotent
                let absolutePoint = topLeftCorner - monitorRect.topLeftCorner
                prevUnhiddenProportionalPositionInsideWorkspaceRect =
                    CGPoint(x: absolutePoint.x / monitorRect.width, y: absolutePoint.y / monitorRect.height)
                if isFloating {
                    lastFloatingSize = windowRect.size
                }
            }
        }
        let p: CGPoint
        switch corner {
            case .bottomLeftCorner:
                guard let s = try await getAxSize(.cancellable) else { fallthrough }
                // Zoom will jump off if you do one pixel offset https://github.com/nikitabobko/AeroSpace/issues/527
                // todo this ad hoc won't be necessary once I implement optimization suggested by Zalim
                let onePixelOffset = macApp.appId == .zoom ? .zero : CGPoint(x: 1, y: -1)
                p = nodeMonitor.visibleRect.bottomLeftCorner + onePixelOffset + CGPoint(x: -s.width, y: 0)
            case .bottomRightCorner:
                // Zoom will jump off if you do one pixel offset https://github.com/nikitabobko/AeroSpace/issues/527
                // todo this ad hoc won't be necessary once I implement optimization suggested by Zalim
                let onePixelOffset = macApp.appId == .zoom ? .zero : CGPoint(x: 1, y: 1)
                p = nodeMonitor.visibleRect.bottomRightCorner - onePixelOffset
        }
        setAxFrame(p, nil)
    }

    func unhideFromCorner() {
        guard let prevUnhiddenProportionalPositionInsideWorkspaceRect else { return }
        guard let nodeWorkspace else { return } // hiding only makes sense for workspace windows

        // Just a small optimization to avoid unnecessary AX calls for non floating windows
        // Tiling windows should be unhidden with layoutWorkspace anyway
        if isFloating {
            let workspaceRect = nodeWorkspace.workspaceMonitor.rect
            var newX = workspaceRect.topLeftX + workspaceRect.width * prevUnhiddenProportionalPositionInsideWorkspaceRect.x
            var newY = workspaceRect.topLeftY + workspaceRect.height * prevUnhiddenProportionalPositionInsideWorkspaceRect.y
            // todo we probably should replace lastFloatingSize with proper floating window sizing
            // https://github.com/nikitabobko/AeroSpace/issues/1519
            let windowWidth = lastFloatingSize?.width ?? 0
            let windowHeight = lastFloatingSize?.height ?? 0
            newX = newX.coerce(in: workspaceRect.minX ... max(workspaceRect.minX, workspaceRect.maxX - windowWidth))
            newY = newY.coerce(in: workspaceRect.minY ... max(workspaceRect.minY, workspaceRect.maxY - windowHeight))

            setAxFrame(CGPoint(x: newX, y: newY), nil)
        }

        self.prevUnhiddenProportionalPositionInsideWorkspaceRect = nil
    }

    override var isHiddenInCorner: Bool {
        prevUnhiddenProportionalPositionInsideWorkspaceRect != nil
    }

    override func getAxSize(_ cm: CancellationMode) async throws -> CGSize? {
        try await macApp.getAxAttr(windowId, Ax.sizeAttr, cm)
    }

    override func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) {
        macApp.setAxFrame(windowId, topLeft, size)
    }

    override func getAxRect(_ cm: CancellationMode) async throws -> Rect? {
        try await macApp.getAxRect(windowId, cm)
    }
}

extension Window {
    func relayoutWindow(on workspace: Workspace, _ cm: CancellationMode, forceTile: Bool = false) async throws {
        let type: AxUiElementWindowType = forceTile
            ? .window
            : try await asMacWindow().macApp.getAxUiElementWindowType(windowId, getWindowLevel(for: windowId), cm)
        // The window or the workspace may be gone after the suspension point above
        guard isAlive, workspace.isAlive else { return }
        let slot = unbindAndGetSlotForNewWindow(type, workspace, window: self)
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
