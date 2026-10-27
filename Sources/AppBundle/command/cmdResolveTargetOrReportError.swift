import Common

extension CmdArgs {
    @MainActor
    func resolveTargetOrReportError(_ env: CmdEnv, _ io: CmdIo) -> LiveFocus? {
        // Flags
        if let windowId {
            return windowFocusOrReportError(windowId, "passed to --window-id", io)
        }
        if let workspaceName {
            return Workspace.get(byName: workspaceName.raw).toLiveFocus()
        }
        // Env
        if let windowId = env.windowId {
            return windowFocusOrReportError(windowId, "specified in \(AEROSPACE_WINDOW_ID) env variable", io)
        }
        if let wsName = env.workspaceName {
            return Workspace.get(byName: wsName).toLiveFocus()
        }
        // Real Focus
        return focus
    }

    /// For the commands that need a window: the target's window
    @MainActor
    func resolveWindowOrReportError(_ env: CmdEnv, _ io: CmdIo, noWindowMsg: String = noWindowIsFocused) -> Window? {
        guard let target = resolveTargetOrReportError(env, io) else { return nil }
        guard let window = target.windowOrNil else {
            io.err(noWindowMsg)
            return nil
        }
        return window
    }
}

@MainActor
private func windowFocusOrReportError(_ windowId: UInt32, _ source: String, _ io: CmdIo) -> LiveFocus? {
    guard let window = Window.get(byId: windowId) else {
        io.err("Invalid <window-id> \(windowId) \(source)")
        return nil
    }
    guard let liveFocus = window.toLiveFocusOrNil() else {
        io.err("Window \(windowId) doesn't belong to any monitor. And thus can't even define a focused workspace")
        return nil
    }
    return liveFocus
}
