import AppKit
import Common

/// This object should be only passed around but never memorized
/// Alternative name: ResolvedFocus
struct LiveFocus: Equatable {
    let workspace: Workspace
    /// The window and where it is on ``workspace``. nil: the workspace is empty
    let windowAndPlacement: (window: Window, placement: WorkspacePlacement)?

    var windowOrNil: Window? { windowAndPlacement?.window }

    static func == (lhs: LiveFocus, rhs: LiveFocus) -> Bool {
        lhs.workspace == rhs.workspace && lhs.windowOrNil == rhs.windowOrNil
    }

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
private struct FrozenFocus: Equatable, Sendable {
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

/// The focus and its history. Part of ``World``
struct FocusStore {
    /// nil until the first read, see `_focus`
    fileprivate var current: FrozenFocus? = nil
    /// What the last on-focus-changed check saw. nil until the first check reads it: then it's the current focus
    fileprivate var lastKnown: FrozenFocus? = nil
    /// Used by focus-back-and-forth
    fileprivate var prev: FrozenFocus? = nil
    /// Used by workspace-back-and-forth
    var prevWorkspaceName: String? = nil {
        didSet { prevWorkspaceDate = .now }
    }
    private(set) var prevWorkspaceDate: Date = .distantPast
    fileprivate var isRunningOnFocusChangedCallbacks = false
    /// See ``syncFocusFromMacOs()``
    var lastKnownNativeFocusedWindowId: UInt32? = nil
}

/// The focus, initialized on the first read from the workspace of the main monitor
private var _focus: FrozenFocus {
    if let current = world.focusStore.current { return current }
    let monitor = mainMonitorInfo
    let initial = FrozenFocus(windowId: nil, workspaceName: monitor.activeWorkspace.name, monitorId_oneBased: monitor.monitorId_oneBased ?? 0)
    world.focusStore.current = initial
    return initial
}

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

    world.focusStore.current = newFrozenFocus
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

    /// nil for the minimized, popup and unbound windows: they aren't on a workspace
    func toLiveFocusOrNil() -> LiveFocus? {
        workspacePlacement.map { LiveFocus(workspace: $0.workspace, windowAndPlacement: (self, $0.placement)) }
    }
}
extension Workspace {
    func focusWorkspace() -> Bool { setFocus(to: toLiveFocus()) }

    func toLiveFocus() -> LiveFocus {
        let window = mostRecentWindowRecursive ?? mostRecentWindowPastEmptyRoot ?? anyLeafWindowRecursive
        // The window is on this workspace, so it has a workspace placement. No window: the workspace is empty
        return window?.toLiveFocusOrNil() ?? LiveFocus(workspace: self, windowAndPlacement: nil)
    }

    /// After the last tiling window closes, the empty root stays the most recent child (RB-77). Then the most recent window
    /// of the other children, instead of the first one in DFS order
    private var mostRecentWindowPastEmptyRoot: Window? {
        guard let root = mostRecentChild as? TilingContainer, root.isEffectivelyEmpty else { return nil }
        return mruChildren.dropFirst().lazy.compactMap(\.mostRecentWindowRecursive).first
    }
}

var prevFocusedWorkspace: Workspace? { world.focusStore.prevWorkspaceName.map { Workspace.get(byName: $0) } }
var prevFocus: LiveFocus? {
    guard let prev = world.focusStore.prev?.live, prev != focus else { return nil }
    return prev
}

/// Tests only: the focus that the test set up is the last known one. Otherwise, the first on-focus-changed check of the
/// test sees no change
func markFocusAsKnownForTests() {
    world.focusStore.lastKnown = _focus
}

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
    let lastKnownFocus = world.focusStore.lastKnown ?? _focus
    let hasFocusChanged = frozenFocus != lastKnownFocus
    let hasFocusedWorkspaceChanged = frozenFocus.workspaceName != lastKnownFocus.workspaceName
    let hasFocusedMonitorChanged = frozenFocus.monitorId_oneBased != lastKnownFocus.monitorId_oneBased
    if hasFocusChanged { world.focusStore.prev = lastKnownFocus }
    if hasFocusedWorkspaceChanged { world.focusStore.prevWorkspaceName = lastKnownFocus.workspaceName }
    world.focusStore.lastKnown = frozenFocus

    if world.focusStore.isRunningOnFocusChangedCallbacks { return }
    world.focusStore.isRunningOnFocusChangedCallbacks = true
    defer { world.focusStore.isRunningOnFocusChangedCallbacks = false }
    if hasFocusChanged {
        _ = await onFocusChanged(.defaultEnv, CmdIo.emptyStdinIgnoringOut, focus)
    }
    if let prevWorkspaceName = world.focusStore.prevWorkspaceName, hasFocusedWorkspaceChanged {
        onWorkspaceChanged(prevWorkspaceName, frozenFocus.workspaceName, focus)
    }
    if hasFocusedMonitorChanged {
        _ = await onFocusedMonitorChanged(.defaultEnv, CmdIo.emptyStdinIgnoringOut, focus)
    }
}

func onFocusedMonitorChanged(_ env: CmdEnv, _ io: CmdIo, _ focus: LiveFocus) async -> Int32 {
    broadcastEvent(.focusedMonitorChanged(
        workspace: focus.workspace.name,
        monitorId_oneBased: focus.workspace.workspaceMonitor.monitorId_oneBased ?? 0,
    ))
    return await config.onFocusedMonitorChanged.run(env.withFocus(focus), io)
}

func onFocusChanged(_ env: CmdEnv, _ io: CmdIo, _ focus: LiveFocus) async -> Int32 {
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
