import AppKit
import Common

struct FlattenWorkspaceTreeCommand: nonisolated Command {
    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var workspace: WorkspaceName? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var result = Self()
        while let option = try a.nextOption() {
            switch option {
                case "--workspace": result.workspace = try a.workspace(of: option)
                default: throw .unknownOption(option)
            }
        }
        try a.end()
        return result
    }

    func run(_ cx: CmdContext) throws(CmdFail) {
        let workspace = try cx.target(workspace: workspace).workspace
        let windows = workspace.rootTilingContainer.allLeafWindowsRecursive
        for window in windows {
            window.bind(to: workspace.rootTilingContainer, weight: 1)
        }
    }
}
