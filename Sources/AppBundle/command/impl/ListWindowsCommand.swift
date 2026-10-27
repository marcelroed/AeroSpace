import AppKit
import Common

struct ListWindowsCommand: Command {
    let args: ListWindowsCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        let focus = focus
        var windows: [Window] = []

        if args.filteringOptions.focused {
            switch focus.windowOrNil {
                case let window?: windows = [window]
                case nil: return .fail(io.err(noWindowIsFocused))
            }
        } else {
            var workspaces: Set<Workspace> = args.filteringOptions.workspaces.isEmpty
                ? Workspace.all.toSet()
                : args.filteringOptions.workspaces
                    .flatMap { filter in
                        switch filter {
                            case .focused: [focus.workspace]
                            case .visible: Workspace.all.filter(\.isVisible)
                            case .name(let name): [Workspace.get(byName: name.raw)]
                        }
                    }
                    .toSet()
            if !args.filteringOptions.monitors.isEmpty {
                let monitors: Set<CGPoint> = args.filteringOptions.monitors.resolveMonitors(io)
                if monitors.isEmpty { return .fail }
                workspaces = workspaces.filter { monitors.contains($0.workspaceMonitor.rect.topLeftCorner) }
            }
            windows = workspaces.flatMap(\.allLeafWindowsRecursive)
            if let pid = args.filteringOptions.pidFilter {
                windows = windows.filter { $0.app.pid == pid }
            }
            if let appId = args.filteringOptions.appIdFilter {
                windows = windows.filter { $0.app.rawAppBundleId == appId }
            }
        }

        if args.outputOnlyCount {
            return .succ(io.out("\(windows.count)"))
        }
        var resolved: [WindowWithPrefetchedTitle] = []
        for window in windows {
            guard let window = try? await WindowWithPrefetchedTitle.resolveWindow(window, for: args.format, .nonCancellable) else { return .fail(io.err(bugPrompt())) }
            resolved.append(window)
        }
        let list = resolved
            .filter { $0.window.isBound }
            // The window ID breaks ties, the windows are collected from a Set of workspaces
            .sorted { a, b in (a.window.app.name ?? "", a.title ?? "", a.window.windowId) < (b.window.app.name ?? "", b.title ?? "", b.window.windowId) }
            .map(AeroObj.window)
        return args.printList(list, io)
    }
}
