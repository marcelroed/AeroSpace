import AppKit
import Common

struct CloseCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var quitIfLastWindow = false
    var windowId: WindowId? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var result = Self()
        while let option = try a.nextOption() {
            switch option {
                case "--quit-if-last-window": result.quitIfLastWindow = true
                case "--window-id": result.windowId = try a.windowId(of: option)
                default: throw .unknownOption(option)
            }
        }
        try a.end()
        return result
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let window = try cx.window(windowId: windowId, noWindowMsg: "Empty workspace")
        // Access ax directly. Not cool :(
        if quitIfLastWindow, (try? await window.asMacWindow().macApp.getAxWindowsCount(.nonCancellable)) == 1 {
            guard window.isAlive else { return } // The window closed at the suspension point above
            let app = window.asMacWindow().macApp
            guard app.nsApp.terminate() else { throw "Failed to quit '\(window.app.name ?? "Unknown app")'" }
            for workspace in Workspace.all {
                for window in workspace.allLeafWindowsRecursive where window.app.pid == app.pid {
                    window.asMacWindow().garbageCollect(skipClosedWindowsCache: true)
                }
            }
        } else {
            window.closeAxWindow()
        }
    }
}

struct CloseAllWindowsButCurrentCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var quitIfLastWindow = false

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var result = Self()
        while let option = try a.nextOption() {
            switch option {
                case "--quit-if-last-window": result.quitIfLastWindow = true
                default: throw .unknownOption(option)
            }
        }
        try a.end()
        return result
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let target = try cx.target()
        guard let focused = target.windowOrNil else { throw "Empty workspace" }
        var failed = false
        // A window that closed meanwhile (e.g. its app quit with --quit-if-last-window) is skipped
        for window in target.workspace.allLeafWindowsRecursive where window != focused && window.isAlive {
            do {
                try await delegate(to: CloseCommand(quitIfLastWindow: quitIfLastWindow), CmdContext(env: cx.env.withWindowId(window.windowId), io: cx.io))
            } catch {
                if let message = error.message { cx.err(message) }
                failed = true
            }
        }
        if failed { throw .silent }
    }
}

struct FullscreenCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var toggle: ToggleEnum = .toggle
    var noOuterGaps = false
    var failIfNoop = false
    var windowId: WindowId? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var result = Self()
        while let option = try a.nextOption() {
            switch option {
                case "--no-outer-gaps": result.noOuterGaps = true
                case "--fail-if-noop": result.failIfNoop = true
                case "--window-id": result.windowId = try a.windowId(of: option)
                default: throw .unknownOption(option)
            }
        }
        if let onOff: OnOff = try a.positional() { result.toggle = onOff.toggle }
        try a.end()
        if result.toggle == .off && result.noOuterGaps { throw "--no-outer-gaps is incompatible with 'off' argument" }
        if result.failIfNoop && result.toggle == .toggle { throw "--fail-if-noop requires 'on' or 'off' argument" }
        return result
    }

    func run(_ cx: CmdContext) throws(CmdFail) {
        let window = try cx.window(windowId: windowId)
        let newState = toggle.resolve(current: window.isFullscreen)
        if newState == window.isFullscreen {
            return try noop(cx, failIfNoop: failIfNoop, newState
                ? "Already fullscreen. Tip: use --fail-if-noop to exit with non-zero code"
                : "Already not fullscreen. Tip: use --fail-if-noop to exit with non-zero code")
        }
        window.isFullscreen = newState
        window.noOuterGapsInFullscreen = noOuterGaps

        // Focus on its own workspace
        window.markAsMostRecentChild()
    }
}

/// Problem ID-B6E178F2: It's not first-class citizen command in AeroSpace model, since it interacts with macOS API directly.
/// Consecutive macos-native-fullscreen commands may not works as expected (because macOS may report correct state with a
/// delay), or may flicker
///
/// The same applies to macos-native-minimize command
struct MacosNativeFullscreenCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var toggle: ToggleEnum = .toggle
    var failIfNoop = false
    var windowId: WindowId? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var result = Self()
        while let option = try a.nextOption() {
            switch option {
                case "--fail-if-noop": result.failIfNoop = true
                case "--window-id": result.windowId = try a.windowId(of: option)
                default: throw .unknownOption(option)
            }
        }
        if let onOff: OnOff = try a.positional() { result.toggle = onOff.toggle }
        try a.end()
        if result.failIfNoop && result.toggle == .toggle { throw "--fail-if-noop requires 'on' or 'off' argument" }
        return result
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let window = try cx.window(windowId: windowId)
        guard let prevState = try? await window.isMacosFullscreen(.nonCancellable) else { throw CmdFail(bugPrompt()) }
        guard window.isAlive else { return } // The window closed at the suspension point above
        let newState = toggle.resolve(current: prevState)
        if newState == prevState {
            return try noop(cx, failIfNoop: failIfNoop, (newState ? "Already fullscreen. " : "Already not fullscreen. ") +
                "Tip: use --fail-if-noop to exit with non-zero code")
        }
        window.asMacWindow().setNativeFullscreen(newState)
        guard let workspace = window.nodeWorkspace else {
            throw CmdFail(windowIsntPartOfTree(window))
        }
        if newState { // Enter fullscreen
            window.move(to: workspace.containerCreatingIfNeeded(.macosFullscreen), weight: .value(1))
        } else { // Exit fullscreen
            do {
                if case .macos(let prevParentKind) = window.layoutReason {
                    try await exitMacOsNativeUnconventionalState(
                        window: window,
                        prevParentKind: prevParentKind,
                        workspace: workspace,
                        .nonCancellable,
                    )
                } else {
                    try await window.relayoutWindow(on: workspace, .nonCancellable)
                }
            } catch {
                throw CmdFail(bugPrompt())
            }
        }
    }
}

/// See: MacosNativeFullscreenCommand. Problem ID-B6E178F2
struct MacosNativeMinimizeCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var windowId: WindowId? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var result = Self()
        while let option = try a.nextOption() {
            switch option {
                case "--window-id": result.windowId = try a.windowId(of: option)
                default: throw .unknownOption(option)
            }
        }
        try a.end()
        return result
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        // resolveTargetOrReportError on already minimized windows will always fail
        // It would be easier if minimized windows were part of the workspace in tree hierarchy
        let window = try cx.window(windowId: windowId)
        guard let newState: Bool = try? await !window.isMacosMinimized(.nonCancellable) else { throw CmdFail(bugPrompt()) }
        guard window.isAlive else { return } // The window closed at the suspension point above
        window.asMacWindow().setNativeMinimized(newState)
        if newState { // minimize
            window.move(to: macosMinimizedWindowsContainer, weight: .value(1))
            return
        } else { // unminimize
            throw CmdFail("The command is uncapable of unminimizing windows yet. Sorry") // dead code. should never be possible, see the comment above
        }
    }
}
