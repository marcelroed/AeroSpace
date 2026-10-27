import AppKit
import Common

struct ListModesCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var current = false
    var count = false
    var json = false

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var result = Self()
        while let option = try a.nextOption() {
            switch option {
                case "--count": result.count = true
                case "--current": result.current = true
                case "--json": result.json = true
                default: throw .unknownOption(option)
            }
        }
        try a.end()
        if result.count && result.current { throw .conflicting("--count", "--current") }
        if result.count && result.json { throw .conflicting("--count", "--json") }
        return result
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let modes: [String] = current ? [activeMode ?? mainModeId] : config.modes.keys.sorted()
        if count {
            cx.out("\(modes.count)")
        } else if json {
            guard let json = JSONEncoder.aeroSpaceDefault.encodeToString(modes.map { ["mode-id": $0] }) else {
                throw "Failed to encode JSON"
            }
            cx.out(json)
        } else {
            cx.out(modes)
        }
    }
}
