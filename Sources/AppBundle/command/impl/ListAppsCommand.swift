import AppKit
import Common

struct ListAppsCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var macosHidden: Bool? = nil
    var output: ListOutput = .lines(defaultFormat)

    static let defaultFormat: [FormatToken] = [
        .interVar(.appPid), .interVar(.rightPadding), .literal(" | "),
        .interVar(.appBundleId), .interVar(.rightPadding), .literal(" | "),
        .interVar(.appName),
    ]

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var result = Self()
        var output = ListOutput.Options()
        while let option = try a.nextOption() {
            switch option {
                case "--macos-native-hidden": result.macosHidden = a.noOrTrue()
                default: if try !output.take(option, &a, .app) { throw .unknownOption(option) }
            }
        }
        try a.end()
        result.output = try output.build(defaultFormat: defaultFormat)
        return result
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        var result = MacApp.allAppsMap.values.sorted { ($0.name ?? "", $0.pid) < ($1.name ?? "", $1.pid) }
        if let hidden = macosHidden {
            result = result.filter { $0.nsApp.isHidden == hidden }
        }
        try output.print(result.map(AeroObj.app), cx)
    }
}
