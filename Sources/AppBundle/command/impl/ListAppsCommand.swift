import AppKit
import Common

struct ListAppsCommand: Command {
    let args: ListAppsCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        var result = MacApp.allAppsMap.values.sorted { ($0.name ?? "", $0.pid) < ($1.name ?? "", $1.pid) }
        if let hidden = args.macosHidden {
            result = result.filter { $0.nsApp.isHidden == hidden }
        }

        if args.outputOnlyCount {
            return .succ(io.out("\(result.count)"))
        }
        return args.printList(result.map(AeroObj.app), io)
    }
}
