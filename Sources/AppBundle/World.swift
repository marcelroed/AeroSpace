import AppKit
import Common

/// The model: the workspaces and their trees, the global containers, the monitors and their workspaces, the focus, the
/// closed-windows cache, the loaded config and active mode, and the window manager's pending state. Tests start each
/// case from a fresh one: ``reset()``.
///
/// A class while the nodes are classes: a copy wouldn't copy the trees. Each property is a separate access, so writing one
/// property doesn't conflict with reading another
final class World {
    /// See ``Workspace/get(byName:)`` and ``Workspace/garbageCollectUnusedWorkspaces()``
    var workspacesByName: [String: Workspace] = [:] {
        didSet { sortedWorkspaces = nil }
    }
    /// ``Workspace/all``, sorted on the first read after a workspace was created or garbage collected
    var sortedWorkspaces: [Workspace]? = nil
    /// The minimized windows. A root, like ``macosPopupWindowsContainer``: they aren't part of any workspace
    private(set) var macosMinimizedWindowsContainer: Container = Container(root: .macosMinimized)
    /// The objects that are windows from the AX perspective, but not even dialogs from the human perspective
    private(set) var macosPopupWindowsContainer: Container = Container(root: .macosPopup)
    /// Every window, bound or not, from its registration until it's garbage collected. See ``Window/get(byId:)``
    var windows: [WindowId: Window] = [:]
    /// See ``TreeNode/markAsMostRecentChild()``
    var mruClock: UInt64 = 0
    /// The monitors of the current session, see ``updateMonitors(_:)``
    var monitors: Monitors = .beforeFirstSnapshot
    var assignment: MonitorAssignment = MonitorAssignment()
    var focusStore: FocusStore = FocusStore()
    /// First line of defence against lock screen
    ///
    /// When you lock the screen, all accessibility API becomes unobservable (all attributes become empty, window id
    /// becomes nil, etc.) which tricks AeroSpace into thinking that all windows were closed.
    /// That's why every time a window dies AeroSpace caches the "entire world" (unless window is already presented in the
    /// cache) so that once the screen is unlocked, AeroSpace could restore windows to where they were
    var closedWindowsCache: FrozenWorld = FrozenWorld(workspaces: [], monitors: [], windowIds: [])
    /// The config that reload-config applied last, and the file it came from
    var config: Config = defaultConfig
    var configUrl: URL = defaultConfigUrl
    /// The mode whose bindings are active. nil while the server is disabled. A removed mode keeps its stale name
    var activeMode: String? = mainModeId
    /// Set by `layout --for-next-detected-window`, taken by the next window that on-window-detected sees
    var layoutForNextDetectedWindow: LayoutCommand.LayoutDescription? = nil
    /// The window that the user moves or resizes with the mouse. Layout leaves it where the mouse puts it
    var mouseManipulatedWindowId: WindowId? = nil
    var debugWindows: DebugWindowsRecording = .off
    /// Is window management on (`enable on|off`). While it's off, the sessions skip everything but `enable`
    var isEnabled: Bool = true {
        didSet { ui.trayMenuModel.isEnabled = isEnabled } // The menu bar observes the model, not the world
    }
    /// The models of the menu bar and the message window. The same instance for the app's lifetime: the scenes hold it
    let ui: Ui
    /// The funnel for every session, see Sessions.swift
    let sessions: Sessions

    init() {
        ui = Ui()
        sessions = Sessions()
    }

    /// The fresh world of ``reset()``. It shares `ui` and `sessions`, so it doesn't build a menu bar model
    private init(sharingUiAndSessionsOf other: World) {
        ui = other.ui
        sessions = other.sessions
    }

    /// Tests only: puts every property back to its initial value. A property that it misses leaks from test to test
    func reset() {
        let fresh = World(sharingUiAndSessionsOf: self)
        workspacesByName = fresh.workspacesByName
        sortedWorkspaces = fresh.sortedWorkspaces
        macosMinimizedWindowsContainer = fresh.macosMinimizedWindowsContainer
        macosPopupWindowsContainer = fresh.macosPopupWindowsContainer
        windows = fresh.windows
        mruClock = fresh.mruClock
        monitors = fresh.monitors
        assignment = fresh.assignment
        focusStore = fresh.focusStore
        closedWindowsCache = fresh.closedWindowsCache
        config = fresh.config
        configUrl = fresh.configUrl
        activeMode = fresh.activeMode
        layoutForNextDetectedWindow = fresh.layoutForNextDetectedWindow
        mouseManipulatedWindowId = fresh.mouseManipulatedWindowId
        debugWindows = fresh.debugWindows
        isEnabled = fresh.isEnabled // The didSet resets the menu bar model's copy
        // `ui` and `sessions` stay. Their state that a test can leave behind:
        ui.messageModel.message = nil
        sessions.cancelHeavy()
    }
}

/// A constant: a `var` would cost a dynamic exclusivity check on every access. Tests use ``World/reset()``
let world: World = World()

var config: Config { world.config }
var macosMinimizedWindowsContainer: Container { world.macosMinimizedWindowsContainer }
var macosPopupWindowsContainer: Container { world.macosPopupWindowsContainer }
