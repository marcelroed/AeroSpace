import AppKit
import Common

/// The model: the workspaces and their trees, the global containers, the monitors and their workspaces, the focus, the
/// closed-windows cache, the loaded config and active mode, and the window manager's pending state. Tests start each
/// case from a fresh one: ``reset(platform:)``.
///
/// A class while the nodes are classes: a copy wouldn't copy the trees. Each property is a separate access, so writing one
/// property doesn't conflict with reading another
final class World {
    /// A workspace exists from its first lookup by name until it's garbage collected: without windows, invisible, unfocused
    /// and not persistent
    var workspacesByName: [String: Workspace] = [:] {
        didSet { sortedWorkspaces = nil }
    }
    /// ``Workspace/all``, sorted on the first read after a workspace was created or garbage collected
    var sortedWorkspaces: [Workspace]? = nil
    /// The minimized windows. A root, like ``macosPopupWindowsContainer``: they aren't part of any workspace
    private(set) var macosMinimizedWindowsContainer: Container = Container(root: .macosMinimized)
    /// The objects that are windows from the AX perspective, but not even dialogs from the human perspective
    private(set) var macosPopupWindowsContainer: Container = Container(root: .macosPopup)
    /// Every window, bound or not, from its registration until it's garbage collected
    var windows: [WindowId: Window] = [:]
    /// The last stamp that ``TreeNode/markAsMostRecentChild()`` gave out. One clock for all the trees, so that the stamp of
    /// a node that moves stays comparable with its new siblings' stamps
    var mruClock: UInt64 = 0
    /// The snapshot of the screens that ``updateMonitors(_:)`` takes at the start of every session
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
    /// The tile that the user moves or resizes with the mouse. Layout leaves it where the mouse puts it
    var mouseManipulatedWindowId: WindowId? = nil
    /// The floating window that the user moves with the mouse, and its center where the drag last read it. Layout leaves it
    /// where the mouse puts it, and the mouse up drops it on that monitor (``dropDraggedFloatingWindow()``)
    var draggedFloatingWindow: (id: WindowId, center: CGPoint)? = nil
    var debugWindows: DebugWindowsRecording = .off
    /// Is window management on (`enable on|off`). While it's off, the sessions skip everything but `enable`
    var isEnabled: Bool = true {
        didSet { ui.trayMenuModel.isEnabled = isEnabled } // The menu bar observes the model, not the world
    }
    /// The models of the menu bar and the message window. The same instance for the app's lifetime: the scenes hold it
    let ui: Ui
    /// Every input that reads or changes the model (a hotkey, a CLI request, an AX notification, ...) enters through it
    let sessions: Sessions
    /// macOS: the only way to the windows, the apps, the screens and the mouse. The app creates the live one at its first
    /// use; a test installs a fake before (``reset(platform:)``)
    private(set) lazy var platform: any Platform = {
        checkIsAeroSpaceApp("LivePlatform (a test installs FakePlatform with setUpWorkspacesForTests())")
        return LivePlatform()
    }()

    init() {
        ui = Ui()
        sessions = Sessions()
    }

    /// The fresh world of ``reset(platform:)``. It shares `ui` and `sessions`, so it doesn't build a menu bar model
    init(sharingUiAndSessionsOf other: World, platform: any Platform) {
        ui = other.ui
        sessions = other.sessions
        self.platform = platform
    }

    /// Tests only: puts every property back to its initial value. WorldResetTest fails for a property that it misses
    func reset(platform: any Platform) {
        let fresh = World(sharingUiAndSessionsOf: self, platform: platform)
        self.platform = fresh.platform
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
        draggedFloatingWindow = fresh.draggedFloatingWindow
        debugWindows = fresh.debugWindows
        isEnabled = fresh.isEnabled // The didSet resets the menu bar model's copy
        // `ui` and `sessions` stay. Their state that a test can leave behind:
        ui.messageModel.message = nil
        sessions.cancelHeavy()
    }
}

/// A constant: a `var` would cost a dynamic exclusivity check on every access. Tests use ``World/reset(platform:)``
let world: World = World()

var config: Config { world.config }
var macosMinimizedWindowsContainer: Container { world.macosMinimizedWindowsContainer }
var macosPopupWindowsContainer: Container { world.macosPopupWindowsContainer }
