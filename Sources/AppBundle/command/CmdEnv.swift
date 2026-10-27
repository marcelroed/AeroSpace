import Common

struct CmdEnv {
    var windowId: WindowId? = nil
    var workspaceName: String? = nil

    static let defaultEnv: CmdEnv = .init()

    consuming func withFocus(_ focus: LiveFocus) -> Self {
        if let window = focus.windowOrNil { withWindowId(window.windowId) } else { withWorkspaceName(focus.workspace.name) }
    }

    consuming func withWindowId(_ windowId: WindowId) -> CmdEnv {
        self.windowId = windowId
        self.workspaceName = nil
        return self
    }

    consuming func withWorkspaceName(_ workspaceName: String) -> CmdEnv {
        self.windowId = nil
        self.workspaceName = workspaceName
        return self
    }

    var asMap: [String: String] {
        var result = [String: String]()
        if let windowId {
            result[AEROSPACE_WINDOW_ID] = windowId.description
        }
        if let workspaceName {
            result[AEROSPACE_WORKSPACE] = workspaceName
        }
        return result
    }
}
