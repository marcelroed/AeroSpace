func initSubcommands() -> [String: SubCommandParser] {
    var result: [String: SubCommandParser] = [:]
    for kind in CmdKind.allCases {
        switch kind {
            case .balanceSizes:
                result[kind.rawValue] = SubCommandParser(BalanceSizesCmdArgs.init)
            case .close:
                result[kind.rawValue] = SubCommandParser(CloseCmdArgs.init)
            case .closeAllWindowsButCurrent:
                result[kind.rawValue] = SubCommandParser(CloseAllWindowsButCurrentCmdArgs.init)
            case .config:
                result[kind.rawValue] = SubCommandParser(parseConfigCmdArgs)
            case .debugWindows:
                result[kind.rawValue] = SubCommandParser(DebugWindowsCmdArgs.init)
            case .echo:
                result[kind.rawValue] = SubCommandParser(EchoCmdArgs.init)
            case .enable:
                result[kind.rawValue] = SubCommandParser(parseEnableCmdArgs)
            case .eval:
                result[kind.rawValue] = SubCommandParser(EvalCmdArgs.init)
            case .execAndForget:
                break // exec-and-forget is parsed separately
            case ._false:
                result[kind.rawValue] = SubCommandParser(FalseCmdArgs.init)
            case .flattenWorkspaceTree:
                result[kind.rawValue] = SubCommandParser(FlattenWorkspaceTreeCmdArgs.init)
            case .focus:
                result[kind.rawValue] = SubCommandParser(parseFocusCmdArgs)
            case .focusBackAndForth:
                result[kind.rawValue] = SubCommandParser(FocusBackAndForthCmdArgs.init)
            case .focusMonitor:
                result[kind.rawValue] = SubCommandParser(parseFocusMonitorCmdArgs)
            case .fullscreen:
                result[kind.rawValue] = SubCommandParser(parseFullscreenCmdArgs)
            case .joinWith:
                result[kind.rawValue] = SubCommandParser(JoinWithCmdArgs.init)
            case .layout:
                result[kind.rawValue] = SubCommandParser(parseLayoutCmdArgs)
            case .listApps:
                result[kind.rawValue] = SubCommandParser(parseListAppsCmdArgs)
            case .listExecEnvVars:
                result[kind.rawValue] = SubCommandParser(ListExecEnvVarsCmdArgs.init)
            case .listModes:
                result[kind.rawValue] = SubCommandParser(ListModesCmdArgs.init)
            case .listMonitors:
                result[kind.rawValue] = SubCommandParser(parseListMonitorsCmdArgs)
            case .listWindows:
                result[kind.rawValue] = SubCommandParser(parseListWindowsCmdArgs)
            case .listWorkspaces:
                result[kind.rawValue] = SubCommandParser(parseListWorkspacesCmdArgs)
            case .macosNativeFullscreen:
                result[kind.rawValue] = SubCommandParser(parseMacosNativeFullscreenCmdArgs)
            case .macosNativeMinimize:
                result[kind.rawValue] = SubCommandParser(MacosNativeMinimizeCmdArgs.init)
            case .mode:
                result[kind.rawValue] = SubCommandParser(ModeCmdArgs.init)
            case .move:
                result[kind.rawValue] = SubCommandParser(parseMoveCmdArgs)
                // deprecated
                result["move-through"] = SubCommandParser(parseMoveCmdArgs)
            case .moveMouse:
                result[kind.rawValue] = SubCommandParser(parseMoveMouseCmdArgs)
            case .moveNodeToMonitor:
                result[kind.rawValue] = SubCommandParser(parseMoveNodeToMonitorCmdArgs)
            case .moveNodeToWorkspace:
                result[kind.rawValue] = SubCommandParser(parseMoveNodeToWorkspaceCmdArgs)
            case .moveWorkspaceToMonitor:
                result[kind.rawValue] = SubCommandParser(parseMoveWorkspaceToMonitorCmdArgs)
                // deprecated
                result["move-workspace-to-display"] = SubCommandParser(MoveWorkspaceToMonitorCmdArgs.init)
            case .reloadConfig:
                result[kind.rawValue] = SubCommandParser(ReloadConfigCmdArgs.init)
            case .resize:
                result[kind.rawValue] = SubCommandParser(parseResizeCmdArgs)
            case .runCallback:
                result[kind.rawValue] = SubCommandParser(parseRunCallbackCmdArgs)
            case .split:
                result[kind.rawValue] = SubCommandParser(parseSplitCmdArgs)
            case .subscribe:
                result[kind.rawValue] = SubCommandParser(parseSubscribeCmdArgs)
            case .summonWorkspace:
                result[kind.rawValue] = SubCommandParser(SummonWorkspaceCmdArgs.init)
            case .swap:
                result[kind.rawValue] = SubCommandParser(SwapCmdArgs.init)
            case .test:
                result[kind.rawValue] = SubCommandParser(TestCmdArgs.init)
            case .testNot:
                result[kind.rawValue] = SubCommandParser(parseTestNotCmdArgs)
            case .triggerBinding:
                result[kind.rawValue] = SubCommandParser(parseTriggerBindingCmdArgs)
            case ._true:
                result[kind.rawValue] = SubCommandParser(TrueCmdArgs.init)
            case .volume:
                result[kind.rawValue] = SubCommandParser(VolumeCmdArgs.init)
            case .workspace:
                result[kind.rawValue] = SubCommandParser(parseWorkspaceCmdArgs)
            case .workspaceBackAndForth:
                result[kind.rawValue] = SubCommandParser(WorkspaceBackAndForthCmdArgs.init)
        }
    }
    return result
}
