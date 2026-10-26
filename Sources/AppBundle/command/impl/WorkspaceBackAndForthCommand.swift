import AppKit
import Common

struct WorkspaceBackAndForthCommand: Command {
    let args: WorkspaceBackAndForthCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        switch prevFocusedWorkspace {
            case let prevFocusedWorkspace?: .from(bool: prevFocusedWorkspace.focusWorkspace())
            case nil: .fail(io.err("There is no previously focused workspace"))
        }
    }
}
