import AppKit
import Common

struct BalanceSizesCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
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
        balance(try cx.target(workspace: workspace).workspace.rootTilingContainer)
    }
}

private func balance(_ parent: TilingContainer) {
    for child in parent.children {
        switch parent.layout {
            case .tiles: child.setWeight(parent.orientation, 1)
            case .accordion: break // Do nothing
        }
        if let child = child as? TilingContainer {
            balance(child)
        }
    }
}
