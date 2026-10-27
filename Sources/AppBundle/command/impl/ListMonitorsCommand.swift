import AppKit
import Common

struct ListMonitorsCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var focused: Bool? = nil
    var mouse: Bool? = nil
    var output: ListOutput = .lines(defaultFormat)

    static let defaultFormat: [FormatToken] = [
        .interVar(.monitorId), .interVar(.rightPadding), .literal(" | "),
        .interVar(.monitorName),
    ]

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var result = Self()
        var output = ListOutput.Options()
        while let option = try a.nextOption() {
            switch option {
                case "--focused": result.focused = a.noOrTrue()
                case "--mouse": result.mouse = a.noOrTrue()
                default: if try !output.take(option, &a, .monitor) { throw .unknownOption(option) }
            }
        }
        try a.end()
        result.output = try output.build(defaultFormat: defaultFormat)
        return result
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let focus = focus
        var result = sortedMonitorInfos
        if let focused {
            result = result.filter { (monitor) in (monitor.activeWorkspace == focus.workspace) == focused }
        }
        if let mouse {
            let mouseWorkspace = mouseLocation.monitorApproximation.activeWorkspace
            result = result.filter { (monitor) in (monitor.activeWorkspace == mouseWorkspace) == mouse }
        }
        try output.print(result.map(AeroObj.monitor), cx)
    }
}
