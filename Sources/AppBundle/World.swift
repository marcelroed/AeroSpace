import AppKit

/// The model: the workspaces and their trees, the global containers, the monitor assignment, the focus and the
/// closed-windows cache. Tests start each case from a fresh one: `world = World()`.
///
/// A class while the nodes are classes: a copy wouldn't copy the trees. Each property is a separate access, so writing one
/// property doesn't conflict with reading another
final class World {
    /// See ``Workspace/get(byName:)`` and ``Workspace/garbageCollectUnusedWorkspaces()``
    var workspacesByName: [String: Workspace] = [:]
    /// The minimized windows. A root, like ``macosPopupWindowsContainer``: they aren't part of any workspace
    let macosMinimizedWindowsContainer = Container(root: .macosMinimized)
    /// The objects that are windows from the AX perspective, but not even dialogs from the human perspective
    let macosPopupWindowsContainer = Container(root: .macosPopup)
    /// See ``TreeNode/markAsMostRecentChild()``
    var mruClock: UInt64 = 0
    var assignment = MonitorAssignment()
    var focusStore = FocusStore()
    /// First line of defence against lock screen
    ///
    /// When you lock the screen, all accessibility API becomes unobservable (all attributes become empty, window id
    /// becomes nil, etc.) which tricks AeroSpace into thinking that all windows were closed.
    /// That's why every time a window dies AeroSpace caches the "entire world" (unless window is already presented in the
    /// cache) so that once the screen is unlocked, AeroSpace could restore windows to where they were
    var closedWindowsCache = FrozenWorld(workspaces: [], monitors: [], windowIds: [])
}

var world = World()

var macosMinimizedWindowsContainer: Container { world.macosMinimizedWindowsContainer }
var macosPopupWindowsContainer: Container { world.macosPopupWindowsContainer }
