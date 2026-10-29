import Common

struct ServerEvent: Codable, Sendable {
    private let _event: ServerEventType

    private var windowId: UInt32?
    private var workspace: String?
    private var prevWorkspace: String?
    private var monitorId: Int? // 1-based
    private var appBundleId: String?
    private var appName: String?
    private var mode: String?
    private var binding: String?

    var eventType: ServerEventType { _event }

    static func focusChanged(windowId: UInt32?, workspace: String) -> ServerEvent {
        ServerEvent(_event: .focusChanged, windowId: windowId, workspace: workspace)
    }

    static func focusedMonitorChanged(workspace: String, monitorId_oneBased: Int) -> ServerEvent {
        ServerEvent(_event: .focusedMonitorChanged, workspace: workspace, monitorId: monitorId_oneBased)
    }

    static func workspaceChanged(workspace: String, prevWorkspace: String) -> ServerEvent {
        ServerEvent(_event: .workspaceChanged, workspace: workspace, prevWorkspace: prevWorkspace)
    }

    static func modeChanged(mode: String?) -> ServerEvent {
        ServerEvent(_event: .modeChanged, mode: mode)
    }

    static func windowDetected(windowId: UInt32, workspace: String?, appBundleId: String?, appName: String?) -> ServerEvent {
        ServerEvent(_event: .windowDetected, windowId: windowId, workspace: workspace, appBundleId: appBundleId, appName: appName)
    }

    static func bindingTriggered(mode: String, binding: String) -> ServerEvent {
        ServerEvent(_event: .bindingTriggered, mode: mode, binding: binding)
    }
}

/// The events of `subscribe`
enum ServerEventType: String, Codable, CaseIterable, Sendable {
    case focusChanged = "focus-changed"
    case focusedMonitorChanged = "focused-monitor-changed"
    case workspaceChanged = "focused-workspace-changed"
    case modeChanged = "mode-changed"
    case windowDetected = "window-detected"
    case bindingTriggered = "binding-triggered"

    /// The event tells a state, so a new client gets the current one first (see `initialState`). A detection or a key
    /// press tells no state
    var hasInitialState: Bool {
        switch self {
            case .focusChanged, .focusedMonitorChanged, .workspaceChanged, .modeChanged: true
            case .windowDetected, .bindingTriggered: false
        }
    }
}
