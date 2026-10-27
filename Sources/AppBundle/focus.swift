import AppKit
import Common

/// This object should be only passed around but never memorized
/// Alternative name: ResolvedFocus
struct LiveFocus: AeroAny, Equatable {
    let windowOrNil: Window?
    let workspace: Workspace

    fileprivate var frozen: FrozenFocus {
        return FrozenFocus(
            windowId: windowOrNil?.windowId,
            workspaceName: workspace.name,
            monitorId_oneBased: workspace.workspaceMonitor.monitorId_oneBased ?? 0,
        )
    }
}

/// "old", "captured", "frozen in time" Focus
/// It's safe to keep a hard reference to this object.
/// Unlike in LiveFocus, information inside FrozenFocus isn't guaranteed to be self-consistent.
/// window - workspace - monitor relation could change since the moment object was created
private struct FrozenFocus: AeroAny, Equatable, Sendable {
    let windowId: UInt32?
    let workspaceName: String
    // monitorId is not part of the focus. We keep it here only for 'on-focused-monitor-changed' to work
    let monitorId_oneBased: Int

    var live: LiveFocus { // Important: don't access focus.monitorId here. monitorId is not part of the focus. Always prefer workspace
        let window: Window? = windowId.flatMap { Window.get(byId: $0) }
        let workspace = Workspace.get(byName: workspaceName)

        let workspaceFocus = workspace.toLiveFocus()
        let windowFocus = window?.toLiveFocusOrNil() ?? workspaceFocus

        return workspaceFocus.workspace != windowFocus.workspace
            ? workspaceFocus // If window and workspace become separated prefer workspace
            : windowFocus
    }
}

private var _focus: FrozenFocus = {
    let monitor = mainMonitorInfo
    return FrozenFocus(windowId: nil, workspaceName: monitor.activeWorkspace.name, monitorId_oneBased: monitor.monitorId_oneBased ?? 0)
}()

/// Global focus.
/// Commands must be cautious about accessing this property directly. There are legitimate cases.
/// But, in general, commands must firstly check --window-id, --workspace, AEROSPACE_WINDOW_ID env and
/// AEROSPACE_WORKSPACE env before accessing the global focus.
var focus: LiveFocus { _focus.live }

func setFocus(to newFocus: LiveFocus) -> Bool {
    // No screens (e.g., during display reconfiguration): workspaceMonitor is the fake mainMonitorInfo, so don't assign
    // workspaces to monitors. Visible workspaces keep their monitors meanwhile, and they can still be focused
    if !hasScreens && !newFocus.workspace.isVisible { return false }
    let oldFrozenFocus = _focus // Read it before newFocus.frozen. _focus is lazily initialized
    let newFrozenFocus = newFocus.frozen
    if oldFrozenFocus == newFrozenFocus { return true }
    let oldFocus = focus
    // Normalize mruWindow when focus away from a workspace
    if oldFocus.workspace != newFocus.workspace {
        oldFocus.windowOrNil?.markAsMostRecentChild()
    }

    _focus = newFrozenFocus
    let status = !hasScreens || newFocus.workspace.workspaceMonitor.setActiveWorkspace(newFocus.workspace)

    newFocus.windowOrNil?.markAsMostRecentChild()
    return status
}
extension Window {
    func focusWindow() -> Bool {
        // todo We should also exit-native-hidden/unminimize[/exit-native-fullscreen?] window if we want to fix ID-B6E178F2
        //      and retry to focus the window. Otherwise, it's not possible to focus minimized/hidden windows
        guard let focus = toLiveFocusOrNil() else { return false }
        return setFocus(to: focus)
    }

    func toLiveFocusOrNil() -> LiveFocus? { nodeWorkspace.map { LiveFocus(windowOrNil: self, workspace: $0) } }
}
extension Workspace {
    func focusWorkspace() -> Bool { setFocus(to: toLiveFocus()) }

    func toLiveFocus() -> LiveFocus {
        // todo unfortunately mostRecentWindowRecursive may recursively reach empty rootTilingContainer
        //      while floating or macos unconventional windows might be presented
        LiveFocus(windowOrNil: mostRecentWindowRecursive ?? anyLeafWindowRecursive, workspace: self) // nil window: empty workspace
    }
}

private var _lastKnownFocus: FrozenFocus = _focus

// Used by workspace-back-and-forth
var _prevFocusedWorkspaceName: String? = nil {
    didSet {
        prevFocusedWorkspaceDate = .now
    }
}
var prevFocusedWorkspaceDate: Date = .distantPast
var prevFocusedWorkspace: Workspace? { _prevFocusedWorkspaceName.map { Workspace.get(byName: $0) } }

// Used by focus-back-and-forth
private var _prevFocus: FrozenFocus? = nil
var prevFocus: LiveFocus? { _prevFocus?.live.takeIf { $0 != focus } }

/// Tests only: forget the focus history of the previous test
func resetFocusHistoryForTests() {
    _prevFocus = nil
    _lastKnownFocus = _focus // Otherwise, the next checkOnFocusChangedCallbacks restores _prevFocus from it
}

private var onFocusChangedRecursionGuard = false
// Should be called in refreshSession
func checkOnFocusChangedCallbacks_nonCancellable() async {
    if refreshSessionEvent?.isStartup == true {
        return
    }
    // No screens (e.g., during display reconfiguration): the focused monitor is unknown. Keep the last known focus and
    // defer the callbacks until the screens come back. Otherwise, they fire twice: now and when the screens come back
    if !hasScreens { return }
    let focus = focus
    let frozenFocus = focus.frozen
    let lastKnownFocus = _lastKnownFocus
    let hasFocusChanged = frozenFocus != lastKnownFocus
    let hasFocusedWorkspaceChanged = frozenFocus.workspaceName != lastKnownFocus.workspaceName
    let hasFocusedMonitorChanged = frozenFocus.monitorId_oneBased != lastKnownFocus.monitorId_oneBased
    if hasFocusChanged { _prevFocus = lastKnownFocus }
    if hasFocusedWorkspaceChanged { _prevFocusedWorkspaceName = lastKnownFocus.workspaceName }
    _lastKnownFocus = frozenFocus

    if onFocusChangedRecursionGuard { return }
    onFocusChangedRecursionGuard = true
    defer { onFocusChangedRecursionGuard = false }
    if hasFocusChanged {
        _ = await onFocusChanged(.defaultEnv, CmdIo.emptyStdinIgnoringOut, focus)
    }
    if let _prevFocusedWorkspaceName, hasFocusedWorkspaceChanged {
        onWorkspaceChanged(_prevFocusedWorkspaceName, frozenFocus.workspaceName, focus)
    }
    if hasFocusedMonitorChanged {
        _ = await onFocusedMonitorChanged(.defaultEnv, CmdIo.emptyStdinIgnoringOut, focus)
    }
}

func onFocusedMonitorChanged(_ env: CmdEnv, _ io: CmdIo, _ focus: LiveFocus) async -> Int32ExitCode {
    broadcastEvent(.focusedMonitorChanged(
        workspace: focus.workspace.name,
        monitorId_oneBased: focus.workspace.workspaceMonitor.monitorId_oneBased ?? 0,
    ))
    return await config.onFocusedMonitorChanged.run(env.withFocus(focus), io)
}

func onFocusChanged(_ env: CmdEnv, _ io: CmdIo, _ focus: LiveFocus) async -> Int32ExitCode {
    broadcastEvent(.focusChanged(
        windowId: focus.windowOrNil?.windowId,
        workspace: focus.workspace.name,
    ))
    return await config.onFocusChanged.run(env.withFocus(focus), io)
}

private func onWorkspaceChanged(_ oldWorkspace: String, _ newWorkspace: String, _ focus: LiveFocus) {
    broadcastEvent(.workspaceChanged(
        workspace: newWorkspace,
        prevWorkspace: oldWorkspace,
    ))
    if let exec = config.execOnWorkspaceChange.first {
        let process = Process()
        process.executableURL = URL(filePath: exec)
        process.arguments = Array(config.execOnWorkspaceChange.dropFirst())
        var environment = config.execConfig.envVariables
        environment[AEROSPACE_FOCUSED_WORKSPACE] = newWorkspace
        environment[AEROSPACE_PREV_WORKSPACE] = oldWorkspace
        if let window = focus.windowOrNil {
            environment[AEROSPACE_WORKSPACE] = nil
            environment[AEROSPACE_WINDOW_ID] = window.windowId.description
        } else { // Empty workspace
            environment[AEROSPACE_WORKSPACE] = focus.workspace.name
            environment[AEROSPACE_WINDOW_ID] = nil
        }
        process.environment = environment
        _ = Result { try process.run() }
    }
}
