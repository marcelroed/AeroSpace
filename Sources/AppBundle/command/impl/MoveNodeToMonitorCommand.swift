import AppKit
import Common

struct MoveNodeToMonitorCommand: Command {
    let args: MoveNodeToMonitorCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let window = args.resolveWindowOrReportError(env, io) else { return .fail }
        guard let currentMonitor = window.nodeMonitor else {
            return .fail(io.err(windowIsntPartOfTree(window)))
        }
        guard let targetMonitor = args.target.val.resolve(currentMonitor, wrapAround: args.wrapAround)
            .getOrNil(appendErrorTo: &io.stderr) else { return .fail }
        let targetWs = targetMonitor.activeWorkspace
        let index = true == args.target.val.directionOrNil
            .map { dir in dir.isPositive && targetWs.rootTilingContainer.orientation == dir.orientation }
            ? 0
            : INDEX_BIND_LAST
        return moveWindowToWorkspace(
            window,
            targetWs,
            io,
            focusFollowsWindow: args.focusFollowsWindow,
            failIfNoop: args.failIfNoop,
            index: index,
        )
    }
}

func windowIsntPartOfTree(_ window: Window) -> String {
    "Window \(window.windowId) is not part of tree (minimized or hidden)"
}
