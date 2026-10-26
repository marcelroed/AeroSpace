import AppKit
import Common

struct CloseCommand: Command {
    let args: CloseCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        guard let window = args.resolveWindowOrReportError(env, io, noWindowMsg: "Empty workspace") else { return .fail }
        // Access ax directly. Not cool :(
        if await args.quitIfLastWindow.andAsync({ @MainActor @Sendable in (try? await window.asMacWindow().macApp.getAxWindowsCount(.nonCancellable)) == 1 }) {
            let app = window.asMacWindow().macApp
            if app.nsApp.terminate() {
                for workspace in Workspace.all {
                    for window in workspace.allLeafWindowsRecursive where window.app.pid == app.pid {
                        window.asMacWindow().garbageCollect(skipClosedWindowsCache: true)
                    }
                }
                return .succ
            } else {
                return .fail(io.err("Failed to quit '\(window.app.name ?? "Unknown app")'"))
            }
        } else {
            window.closeAxWindow()
            return .succ
        }
    }
}
