import AppKit
import Common

struct EnableCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var targetState: ToggleEnum
    var failIfNoop = false

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var failIfNoop = false
        while let option = try a.nextOption() {
            switch option {
                case "--fail-if-noop": failIfNoop = true
                default: throw .unknownOption(option)
            }
        }
        let targetState: ToggleEnum = try a.positional()
        try a.end()
        if targetState == .toggle && failIfNoop { throw "--fail-if-noop is incompatible with 'toggle' argument" }
        return Self(targetState: targetState, failIfNoop: failIfNoop)
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let prevState = TrayMenuModel.shared.isEnabled
        let newState = targetState.resolve(current: prevState)
        if newState == prevState {
            return try noop(cx, failIfNoop: failIfNoop, newState
                ? "Already enabled. Tip: use --fail-if-noop to exit with non-zero code"
                : "Already disabled. Tip: use --fail-if-noop to exit with non-zero code")
        }
        // No screens (e.g., during display reconfiguration). Disabling unhides the windows of all workspaces and lays
        // them out on the fake mainMonitorInfo, and nothing lays them out again while AeroSpace is disabled
        if !newState && !hasScreens { throw "Can't disable \(aeroSpaceAppName) while there are no screens" }
        TrayMenuModel.shared.isEnabled = newState
        if newState {
            for workspace in Workspace.all {
                for window in workspace.allLeafWindowsRecursive where window.isFloating {
                    window.lastFloatingSize = (try? await window.getAxSize(.nonCancellable)) ?? window.lastFloatingSize
                }
            }
            await activateMode_nonCancellable(mainModeId)
        } else {
            await activateMode_nonCancellable(nil)
        }
    }
}
