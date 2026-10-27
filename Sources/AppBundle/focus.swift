import AppKit
import Common

/// This object should be only passed around but never memorized
/// Alternative name: ResolvedFocus
struct LiveFocus: Equatable {
    let workspace: Workspace
    /// The window and where it is on ``workspace``. nil: the workspace is empty
    let windowAndPlacement: (window: Window, placement: WorkspacePlacement)?

    var windowOrNil: Window? { windowAndPlacement?.window }

    /// Whether the workspace still exists and the window is still on it. A command that holds a focus across an `await`
    /// checks it after the await, and skips its work if it's false (stale-object policy)
    var isValid: Bool { workspace.isAlive && windowOrNil.map { $0.toLiveFocusOrNil() == self } ?? true }

    static func == (lhs: LiveFocus, rhs: LiveFocus) -> Bool {
        lhs.workspace == rhs.workspace && lhs.windowOrNil == rhs.windowOrNil
    }

    fileprivate var frozen: FrozenFocus {
        return FrozenFocus(
            windowId: windowOrNil?.windowId,
            workspaceName: workspace.name,
            monitorId_oneBased: workspace.workspaceMonitor.monitorId_oneBased,
        )
    }
}

/// "old", "captured", "frozen in time" Focus
/// It's safe to keep a hard reference to this object.
/// Unlike in LiveFocus, information inside FrozenFocus isn't guaranteed to be self-consistent.
/// window - workspace - monitor relation could change since the moment object was created
private struct FrozenFocus: Equatable, Sendable {
    let windowId: WindowId?
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
    /// What the last on-focus-changed check saw. nil until the callbacks are armed at the end of the startup: until then,
    /// no check reports a change
    fileprivate var lastKnown: FrozenFocus? = nil
    /// Used by focus-back-and-forth
    fileprivate var prev: FrozenFocus? = nil
    /// Used by workspace-back-and-forth
    var prevWorkspaceName: String? = nil {
        didSet { prevWorkspaceDate = .now }
    }
    private(set) var prevWorkspaceDate: Date = .distantPast
    fileprivate var isRunningOnFocusChangedCallbacks = false
    /// The changes whose callbacks wait for the running ones, as one change. See ``runFocusChangedCallbacks(_:)``
    fileprivate var pendingFocusChange: RecordedFocusChange? = nil
    /// See ``syncFocusFromMacOs(_:)``
    var lastKnownNativeFocusedWindowId: WindowId? = nil
    /// The native focus that a session read last, also when the read changed nothing: it was
    /// `lastKnownNativeFocusedWindowId` already, or it's a new window that takes the focus after its callbacks. Such a
    /// window takes the focus only while it's still this one (R2b M1, R2c M1)
    var lastReadNativeFocusedWindowId: WindowId? = nil
}

/// The focus, initialized on the first read from the workspace of the main monitor
private var _focus: FrozenFocus {
    if let current = world.focusStore.current { return current }
    let monitor = world.monitors.main
    let initial = FrozenFocus(windowId: nil, workspaceName: monitor.activeWorkspace.name, monitorId_oneBased: monitor.monitorId_oneBased)
    world.focusStore.current = initial
    return initial
}

/// Global focus.
/// Commands must be cautious about accessing this property directly. There are legitimate cases.
/// But, in general, commands must firstly check --window-id, --workspace, AEROSPACE_WINDOW_ID env and
/// AEROSPACE_WORKSPACE env before accessing the global focus.
var focus: LiveFocus { _focus.live }

func setFocus(to newFocus: LiveFocus) -> Bool {
    // No screens (e.g., during display reconfiguration): don't show other workspaces on the monitors that macOS doesn't
    // report meanwhile. The visible workspaces keep their monitors, and they can still be focused
    if !world.monitors.hasScreens && !newFocus.workspace.isVisible { return false }
    let oldFrozenFocus = _focus // Read it before newFocus.frozen. _focus is lazily initialized
    let newFrozenFocus = newFocus.frozen
    if oldFrozenFocus == newFrozenFocus { return true }
    let oldFocus = focus
    // Normalize mruWindow when focus away from a workspace
    if oldFocus.workspace != newFocus.workspace {
        oldFocus.windowOrNil?.markAsMostRecentChild()
    }

    world.focusStore.current = newFrozenFocus
    let status = !world.monitors.hasScreens || newFocus.workspace.workspaceMonitor.setActiveWorkspace(newFocus.workspace)

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

/// The end of the startup: the focus callbacks report the changes from now on. Tests arm them in
/// setUpWorkspacesForTests
func armFocusChangedCallbacks() {
    world.focusStore.lastKnown = _focus
}

/// Runs the callbacks of a focus change since the last check. Every session runs it in its model refresh
func checkOnFocusChangedCallbacks_nonCancellable() async {
    if let change = recordFocusChange() { await runFocusChangedCallbacks(change) }
}

/// A focus change, see ``recordFocusChange()``
struct RecordedFocusChange {
    fileprivate let prev: FrozenFocus
    fileprivate let focus: FrozenFocus

    /// The workspace that the focus left. nil if the focused workspace didn't change
    fileprivate var prevWorkspaceName: String? { prev.workspaceName == focus.workspaceName ? nil : prev.workspaceName }
    fileprivate var isMonitorChanged: Bool { prev.monitorId_oneBased != focus.monitorId_oneBased }

    /// This change, then `next`, as one change. nil if they cancel out
    fileprivate func then(_ next: RecordedFocusChange) -> RecordedFocusChange? {
        prev == next.focus ? nil : RecordedFocusChange(prev: prev, focus: next.focus)
    }
}

/// The bookkeeping half of the focus check: remembers the previous focus (focus-back-and-forth) and the previous
/// workspace (workspace-back-and-forth, the GC's refocus rule #1089). nil if nothing changed or the callbacks aren't armed
func recordFocusChange() -> RecordedFocusChange? {
    // No screens (e.g., during display reconfiguration): keep the last known focus and defer the callbacks until the screens
    // come back. Their commands would mostly fail meanwhile (focus-monitor, summon-workspace, focusing a hidden workspace)
    guard let lastKnownFocus = world.focusStore.lastKnown, world.monitors.hasScreens else { return nil }
    let frozenFocus = focus.frozen
    if frozenFocus == lastKnownFocus { return nil }
    world.focusStore.prev = lastKnownFocus
    let change = RecordedFocusChange(prev: lastKnownFocus, focus: frozenFocus)
    if let prevWorkspaceName = change.prevWorkspaceName { world.focusStore.prevWorkspaceName = prevWorkspaceName }
    world.focusStore.lastKnown = frozenFocus
    return change
}

/// The callbacks half of the focus check: on-focus-changed, exec-on-workspace-change, on-focused-monitor-changed. One
/// change at a time, in the order of the changes:
/// - A change that a callback's own commands make records it without running the callbacks again: no recursion.
/// - Other sessions' changes while the callbacks suspend (e.g. hotkeys while a callback reads AX) run the callbacks
///   right after them, in the task that runs them (R2c L2). That session doesn't wait for them. Those changes run the
///   callbacks once, as one change to the latest focus: no callback runs for a focus that the user has left (R2d L1)
func runFocusChangedCallbacks(_ change: RecordedFocusChange) async {
    if world.focusStore.isRunningOnFocusChangedCallbacks {
        if FocusChangedCallbacks.isRunningInThisTask { return }
        if let pending = world.focusStore.pendingFocusChange {
            world.focusStore.pendingFocusChange = pending.then(change)
        } else {
            world.focusStore.pendingFocusChange = change
        }
        return
    }
    world.focusStore.isRunningOnFocusChangedCallbacks = true
    defer { world.focusStore.isRunningOnFocusChangedCallbacks = false }
    var next: RecordedFocusChange? = change
    while let change = next {
        await FocusChangedCallbacks.$isRunningInThisTask.withValue(true) { await runCallbacks(of: change) }
        next = world.focusStore.pendingFocusChange
        world.focusStore.pendingFocusChange = nil
    }
}

private enum FocusChangedCallbacks {
    /// The callbacks' commands run in the task that runs the callbacks: a focus check in it is one of theirs
    @TaskLocal static var isRunningInThisTask = false
}

private func runCallbacks(of change: RecordedFocusChange) async {
    let focus = change.focus.live
    _ = await onFocusChanged(.defaultEnv, CmdIo.emptyStdinIgnoringOut, focus)
    if let prevWorkspaceName = change.prevWorkspaceName {
        onWorkspaceChanged(prevWorkspaceName, change.focus.workspaceName, focus)
    }
    if change.isMonitorChanged {
        _ = await onFocusedMonitorChanged(.defaultEnv, CmdIo.emptyStdinIgnoringOut, focus)
    }
}

func onFocusedMonitorChanged(_ env: CmdEnv, _ io: CmdIo, _ focus: LiveFocus) async -> Int32 {
    broadcastEvent(.focusedMonitorChanged(
        workspace: focus.workspace.name,
        monitorId_oneBased: focus.workspace.workspaceMonitor.monitorId_oneBased,
    ))
    return await config.onFocusedMonitorChanged.run(env.withFocus(focus), io)
}

func onFocusChanged(_ env: CmdEnv, _ io: CmdIo, _ focus: LiveFocus) async -> Int32 {
    broadcastEvent(.focusChanged(
        windowId: focus.windowOrNil?.windowId.raw,
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
