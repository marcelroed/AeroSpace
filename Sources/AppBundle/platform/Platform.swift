import AppKit
import Common

/// macOS as the model sees it. The model reaches the windows, the apps, the screens and the mouse only through
/// ``World/platform``: ``LivePlatform`` in the app, a fake in the tests. Keyed by ``WindowId``, never by an AX object.
///
/// - Snapshot reads are synchronous and make no AX call.
/// - Observe reads are the refresh's and the mouse sessions' AX reads. They are abandonable: a cancelled session throws
///   at once, so a hung app can't hold it.
/// - Single reads are the commands' AX reads. They wait for the app, however long it takes. nil: the window or its app is
///   gone.
/// - Effects are fire and forget, FIFO per app.
protocol Platform: AnyObject, Sendable {
    // MARK: Snapshot reads

    /// The monitors as macOS reports them now. Empty while there are no screens (e.g., during display reconfiguration)
    func monitors() -> [MonitorInfo]
    /// Same as `!monitors().isEmpty`, but cheap. For the re-checks after the awaits of a session: the screens can disappear
    /// while it runs, and its snapshot (``World/monitors``) doesn't show that
    var hasScreens: Bool { get }
    /// The registered apps: the regular apps and the other apps whose window got focused
    func runningApps() -> [AppInfo]
    func isHidden(_ app: AppInfo) -> Bool
    var isLeftMouseDown: Bool { get }
    var mouseLocation: CGPoint { get }
    /// The AX calls so far, per call and attribute (e.g. "set AXPosition"), for dogfooding
    var counters: [String: Int] { get }

    // MARK: Observe reads
    // The heavy refresh's reads (Reconcile.swift, P1). Each is one batch: the apps answer in parallel, each on its own
    // thread

    /// The windows of every registered app; registers the new apps. An app that is missing terminated. An app that
    /// doesn't answer by its deadline (see ``ListingDeadlines``) is `.noAnswer`, unless `waitingForEveryApp`
    func listWindows(waitingForEveryApp: Bool) async throws(CancellationError) -> [AppWindows]
    /// The kind and the frame of each window, keyed by its app: the app of a new window is known only from the listing. A
    /// window that is gone is missing, and so is an off-screen window whose kind depends on its level (see
    /// ``AxUiElementMock/getWindowType(axApp:_:_:_:)``): a later refresh classifies it
    func classify(_ windows: [AppInfo: [WindowId]]) async throws(CancellationError) -> [WindowId: DetectedWindow]
    /// A window that is gone is missing
    func nativeFacts(_ windows: [AppInfo: [WindowId]]) async throws(CancellationError) -> [WindowId: NativeFacts]
    /// The focused window of the frontmost app; registers the app. Abandonable: the light session that preempts a heavy
    /// one must not wait for a hung frontmost app
    func focusedWindow() async throws(CancellationError) -> FocusedWindow?
    /// The `debug-windows` dumps of the windows, for a recording. A window that is gone is missing
    func debugInfos(_ windows: [AppInfo: [WindowId]]) async throws(CancellationError) -> [WindowId: WindowDebugInfo]
    /// The mouse sessions' read: a newer mouse event cancels it
    func observedRect(_ id: WindowId) async throws(CancellationError) -> Rect?

    // MARK: Single reads

    func rect(_ id: WindowId) async -> Rect?
    func title(_ id: WindowId) async -> String?
    func facts(_ id: WindowId) async -> NativeFactsRead
    func kind(_ id: WindowId) async -> AxUiElementWindowType?
    func windowCount(_ app: AppInfo) async -> Int?
    func debugInfo(_ id: WindowId) async -> WindowDebugInfo?

    // MARK: Effects

    /// Applies the placements in order. A newer placement of a window makes its pending older one stale
    func apply(_ batch: [Placement])
    /// The window's size now is its floating size (``PlacementState/lastFloatingSize``)
    func rememberFloatingSize(_ id: WindowId)
    func restoreFloatingSize(_ id: WindowId)
    /// Gives the window the native focus: raises it and activates its app
    func focus(_ id: WindowId)
    /// Presses the window's close button
    func close(_ id: WindowId)
    func setNative(_ id: WindowId, _ change: NativeChange)
    func unhideApp(_ app: AppInfo)
    /// Asks the app to quit. false if it refused
    func quit(_ app: AppInfo) -> Bool

    // MARK: Termination

    /// Makes every window visible before AeroSpace exits. On any thread, and it never waits for the main thread
    nonisolated func restoreForTermination()
}

/// The CoreGraphics id of a window: the key of ``World/windows``. The CLI and the JSON output show the raw number
nonisolated struct WindowId: Hashable, Comparable, Sendable, CustomStringConvertible {
    let raw: CGWindowID

    static func < (lhs: WindowId, rhs: WindowId) -> Bool { lhs.raw < rhs.raw }
    var description: String { raw.description }
}

/// An app as it was when the platform registered it
nonisolated struct AppInfo: Hashable, Sendable {
    let pid: pid_t
    let bundleId: String?
    let name: String?
    let execPath: String?
    let bundlePath: String?
    /// The app's bundle id if AeroSpace handles the app specially. Stored: the layout reads it per window
    let knownBundleId: KnownBundleId?

    init(pid: pid_t, bundleId: String?, name: String?, execPath: String?, bundlePath: String?) {
        self.pid = pid
        self.bundleId = bundleId
        self.name = name
        self.execPath = execPath
        self.bundlePath = bundlePath
        knownBundleId = bundleId.flatMap(KnownBundleId.init)
    }
}

nonisolated enum AppWindows: Sendable {
    /// The app's alive windows, in the order the app lists them
    case listed(AppInfo, [WindowId])
    /// The app didn't answer in time (e.g. it's hung). It still has the windows it had: only positive evidence drops one
    case noAnswer(AppInfo)
}

nonisolated struct DetectedWindow: Equatable, Sendable {
    let kind: AxUiElementWindowType
    /// nil if AX doesn't tell
    let rect: Rect?
    /// nil while the window is off-screen (minimized, of a hidden app, on another Space): the window server tells the
    /// levels of the on-screen windows only
    let level: MacOsWindowLevel?

    /// The kind, if it may change a window's classification: an off-screen window's kind is a guess. Its level is unknown,
    /// and macOS gives minimized windows and the windows of hidden apps the AXDialog subrole
    var kindOnScreen: AxUiElementWindowType? { level == nil ? nil : kind }
}

/// The macOS native states of a window that the model mirrors in its containers
nonisolated struct NativeFacts: Equatable, Sendable {
    let isFullscreen: Bool
    /// false if ``isFullscreen``
    let isMinimized: Bool
}

/// A command's read of a window's native states (``Platform/facts(_:)``)
nonisolated enum NativeFactsRead: Equatable, Sendable {
    case facts(NativeFacts)
    /// The window closed, or its app terminated
    case closed
    /// The app didn't answer: the AX timeout of a busy app
    case noAnswer
}

nonisolated struct FocusedWindow: Equatable, Sendable {
    let app: AppInfo
    let windowId: WindowId
}

nonisolated enum NativeChange: Equatable, Sendable {
    case fullscreen(Bool)
    case minimized(Bool)
}

/// What only the platform knows about a window, for `debug-windows`
nonisolated struct WindowDebugInfo: Sendable {
    let axWindow: OrderedJson.JsonDict
    let axApp: OrderedJson.JsonDict
    let windowLevel: MacOsWindowLevel?
    let appVersionShort: String?
    let appVersion: String?
    let activationPolicy: String
    let execUrl: String?
    let bundleUrl: String?
    let isDialog: Bool
    let isWindow: Bool
}
