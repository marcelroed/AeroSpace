import Common

struct EchoCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var args: [[FormatToken]]
    var isStderr = false
    var windowId: UInt32? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var isStderr = false
        var windowId: UInt32? = nil
        while let option = try a.nextOption() {
            switch option {
                case "--stderr": isStderr = true
                case "--window-id": windowId = try a.windowId(of: option)
                default: throw .unknownOption(option)
            }
        }
        let args = try a.allPositionals().map(parseFormat)
        if args.isEmpty { throw "Argument '<string>' is mandatory" }
        return Self(args: args, isStderr: isStderr, windowId: windowId)
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let target = try cx.target(windowId: windowId)
        let obj: AeroObj
        if let window = target.windowOrNil {
            guard let window = try? await WindowWithPrefetchedTitle.resolveWindow(window, for: args.flatMap { $0 }, .nonCancellable) else {
                throw CmdFail(bugPrompt())
            }
            obj = .window(window)
        } else {
            obj = .workspace(target.workspace)
        }
        for arg in args {
            let line: String
            do {
                line = try obj.format(arg)
            } catch {
                throw CmdFail(error.cmdErrorMessage)
            }
            if isStderr { cx.err(line) } else { cx.out(line) }
        }
    }
}
