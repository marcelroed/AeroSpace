import AppKit
import Common

struct EnableCommand: Command {
    let args: EnableCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        let prevState = TrayMenuModel.shared.isEnabled
        let newState = args.targetState.val.resolve(current: prevState)
        if newState == prevState {
            return .noop(io, failIfNoop: args.failIfNoop, newState
                ? "Already enabled. Tip: use --fail-if-noop to exit with non-zero code"
                : "Already disabled. Tip: use --fail-if-noop to exit with non-zero code")
        }
        // No screens (e.g., during display reconfiguration). Disabling unhides the windows of all workspaces and lays
        // them out on the fake mainMonitorInfo, and nothing lays them out again while AeroSpace is disabled
        if !newState && !hasScreens { return .fail(io.err("Can't disable \(aeroSpaceAppName) while there are no screens")) }

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
        return .succ
    }
}
