import AppKit
import Common

protocol Command: AeroAny, Sendable {
    associatedtype T: CmdArgs

    var args: T { get }
    @MainActor
    func run(_ env: CmdEnv, _ io: CmdIo) async -> T.ExitCodeType

    /// We should reset closedWindowsCache when the command can potentially change the tree
    var shouldResetClosedWindowsCache: Bool { get }
}

extension Command {
    /// Command types and their args types are 1:1, so comparing the args compares the commands
    nonisolated func equals(_ other: any Command) -> Bool { args.equals(other.args) }
}

extension Command {
    @MainActor
    @discardableResult
    func run(_ env: CmdEnv, _ stdin: consuming CmdStdin) async -> CmdResult {
        return await Shell.cmd(self).run(env, stdin)
    }
}
