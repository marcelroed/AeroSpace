import AppKit
import Common

struct WorkspaceBackAndForthCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        try a.noArgs()
        return Self()
    }

    func run(_ cx: CmdContext) throws(CmdFail) {
        guard let prevFocusedWorkspace else { throw "There is no previously focused workspace" }
        if !prevFocusedWorkspace.focusWorkspace() { throw .silent }
    }
}
