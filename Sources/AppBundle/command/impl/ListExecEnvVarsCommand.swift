import AppKit
import Common

struct ListExecEnvVarsCommand: Command {
    let args: ListExecEnvVarsCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        for (key, value) in config.execConfig.envVariables.sorted(by: { $0.key < $1.key }) {
            io.out("\(key)=\(value)")
        }
        return .succ
    }
}
