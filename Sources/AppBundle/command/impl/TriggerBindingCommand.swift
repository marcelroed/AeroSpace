import AppKit
import Common

struct TriggerBindingCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var mode: String
    var binding: String

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var mode: String? = nil
        while let option = try a.nextOption() {
            switch option {
                case "--mode": mode = try a.value(of: option, "<mode-id>")
                default: throw .unknownOption(option)
            }
        }
        guard let mode else { throw "--mode flag is mandatory" }
        let result = Self(mode: mode, binding: try a.positional("<binding>"))
        try a.end()
        return result
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        guard let modeBindings = config.modes[mode]?.bindings else {
            throw "Mode '\(mode)' doesn't exist. Available modes: \(config.modes.keys.sorted().joined(separator: ","))"
        }
        guard let match = modeBindings.values.first(where: { $0.descriptionWithKeyNotation == binding }) else {
            throw "Binding '\(binding)' is not presented in mode '\(mode)'"
        }
        // refreshSession is not needed since commands are already run in refreshSession
        let exitCode = await match.commands.run(cx.env, cx.io)
        if exitCode != EXIT_CODE_ZERO { throw CmdFail(nil, exitCode: exitCode) }
    }
}
