/// Every subcommand with its help. The single source of truth for help: the CLI prints it, and SubcommandHelpTest checks
/// that the synopsis and purpose of each docs/aerospace-<subcommand>.adoc match it
public enum CmdKind: String, CaseIterable, Equatable, Sendable {
    case balanceSizes = "balance-sizes"
    case closeAllWindowsButCurrent = "close-all-windows-but-current"
    case close = "close"
    case config = "config"
    case debugWindows = "debug-windows"
    case echo = "echo"
    case enable = "enable"
    case eval = "eval"
    case execAndForget = "exec-and-forget"
    case _false = "false"
    case flattenWorkspaceTree = "flatten-workspace-tree"
    case focusBackAndForth = "focus-back-and-forth"
    case focusMonitor = "focus-monitor"
    case focus = "focus"
    case fullscreen = "fullscreen"
    case joinWith = "join-with"
    case layout = "layout"
    case listApps = "list-apps"
    case listExecEnvVars = "list-exec-env-vars"
    case listModes = "list-modes"
    case listMonitors = "list-monitors"
    case listWindows = "list-windows"
    case listWorkspaces = "list-workspaces"
    case macosNativeFullscreen = "macos-native-fullscreen"
    case macosNativeMinimize = "macos-native-minimize"
    case mode = "mode"
    case moveMouse = "move-mouse"
    case moveNodeToMonitor = "move-node-to-monitor"
    case moveNodeToWorkspace = "move-node-to-workspace"
    case moveWorkspaceToMonitor = "move-workspace-to-monitor"
    case move = "move"
    case reloadConfig = "reload-config"
    case resize = "resize"
    case runCallback = "run-callback"
    case split = "split"
    case subscribe = "subscribe"
    case summonWorkspace = "summon-workspace"
    case swap = "swap"
    case testNot = "test-not"
    case test = "test"
    case triggerBinding = "trigger-binding"
    case _true = "true"
    case volume = "volume"
    case workspaceBackAndForth = "workspace-back-and-forth"
    case workspace = "workspace"

    public var help: String {
        switch self {
            case .balanceSizes:
                """
                USAGE: balance-sizes [-h|--help] [--workspace <workspace>]
                """
            case .closeAllWindowsButCurrent:
                """
                USAGE: close-all-windows-but-current [-h|--help] [--quit-if-last-window]
                """
            case .close:
                """
                USAGE: close [-h|--help] [--quit-if-last-window] [--window-id <window-id>]
                """
            case .config:
                """
                USAGE: config [-h|--help] --get <name> [--json] [--keys]
                   OR: config [-h|--help] --major-keys
                   OR: config [-h|--help] --all-keys
                   OR: config [-h|--help] --config-path
                """
            case .debugWindows:
                """
                USAGE: debug-windows [-h|--help] [--window-id <window-id>]
                """
            case .echo:
                """
                USAGE: echo [-h|--help] [--stderr] [--window-id <window-id>] -- <string>...
                """
            case .enable:
                """
                USAGE: enable [-h|--help] toggle
                   OR: enable [-h|--help] on [--fail-if-noop]
                   OR: enable [-h|--help] off [--fail-if-noop]
                """
            case .eval:
                """
                USAGE: eval [-h|--help] [--stdin] [--] <aerospace-shell-expr>
                """
            case .execAndForget:
                """
                USAGE: exec-and-forget <bash-script>
                """
            case ._false:
                """
                USAGE: false [-h|--help]
                """
            case .flattenWorkspaceTree:
                """
                USAGE: flatten-workspace-tree [-h|--help] [--workspace <workspace>]
                """
            case .focusBackAndForth:
                """
                USAGE: focus-back-and-forth [-h|--help]
                """
            case .focusMonitor:
                """
                USAGE: focus-monitor [-h|--help] [--wrap-around] (left|down|up|right)
                   OR: focus-monitor [-h|--help] [--wrap-around] (next|prev)
                   OR: focus-monitor [-h|--help] [--] <monitor-pattern>...
                """
            case .focus:
                """
                USAGE: focus [-h|--help] [--ignore-floating] [--wrap-around]
                             [--boundaries <boundary>] [--boundaries-action <action>]
                             [--fail-if-fullscreen] [--fail-if-macos-native-fullscreen]
                             (left|down|up|right)
                   OR: focus [-h|--help] [--ignore-floating] [--wrap-around]
                             [--boundaries <boundary>] [--boundaries-action <action>]
                             (dfs-next|dfs-prev)
                   OR: focus [-h|--help] --window-id <window-id>
                   OR: focus [-h|--help] --dfs-index <dfs-index>
                """
            case .fullscreen:
                """
                USAGE: fullscreen [-h|--help]     [--window-id <window-id>] [--no-outer-gaps]
                   OR: fullscreen [-h|--help] on  [--window-id <window-id>] [--no-outer-gaps] [--fail-if-noop]
                   OR: fullscreen [-h|--help] off [--window-id <window-id>] [--fail-if-noop]
                """
            case .joinWith:
                """
                USAGE: join-with [-h|--help] [--window-id <window-id>] (left|down|up|right)
                """
            case .layout:
                """
                USAGE: layout [-h|--help] [--window-id <window-id>|--workspace <workspace>]
                              [--root] [--fail-if-noop]
                              (<target-layout>)...
                   OR: layout [-h|--help] --for-next-detected-window (tiling|floating)
                """
            case .listApps:
                """
                USAGE: list-apps [-h|--help] [--macos-native-hidden [no]] [--format <output-format>] [--count] [--json]
                """
            case .listExecEnvVars:
                """
                USAGE: list-exec-env-vars [-h|--help]
                """
            case .listModes:
                """
                USAGE: list-modes [-h|--help] [--current] [--count] [--json]
                """
            case .listMonitors:
                """
                USAGE: list-monitors [-h|--help] [--focused [no]] [--mouse [no]] [--format <output-format>] [--count] [--json]
                """
            case .listWindows:
                """
                USAGE: list-windows [-h|--help] (--workspace <workspace>...|--monitor <monitor>...)
                                    [--monitor <monitor>...] [--workspace <workspace>...]
                                    [--pid <pid>] [--app-bundle-id <app-bundle-id>] [--format <output-format>]
                                    [--count] [--json]
                   OR: list-windows [-h|--help] --all [--format <output-format>] [--count] [--json]
                   OR: list-windows [-h|--help] --focused [--format <output-format>] [--count] [--json]
                """
            case .listWorkspaces:
                """
                USAGE: list-workspaces [-h|--help] --monitor <monitor>... [--visible [no]] [--empty [no]] [--format <output-format>] [--count] [--json]
                   OR: list-workspaces [-h|--help] --all [--format <output-format>] [--count] [--json]
                   OR: list-workspaces [-h|--help] --focused [--format <output-format>] [--count] [--json]
                """
            case .macosNativeFullscreen:
                """
                USAGE: macos-native-fullscreen [-h|--help] [--window-id <window-id>]
                   OR: macos-native-fullscreen [-h|--help] [--window-id <window-id>] [--fail-if-noop] on
                   OR: macos-native-fullscreen [-h|--help] [--window-id <window-id>] [--fail-if-noop] off
                """
            case .macosNativeMinimize:
                """
                USAGE: macos-native-minimize [-h|--help] [--window-id <window-id>]
                """
            case .mode:
                """
                USAGE: mode [-h|--help] [--] <binding-mode>
                """
            case .moveMouse:
                """
                USAGE: move-mouse [-h|--help] [--fail-if-noop] <mouse-position>
                """
            case .moveNodeToMonitor:
                """
                USAGE: move-node-to-monitor [-h|--help] [--window-id <window-id>] [--focus-follows-window]
                                            [--wrap-around] (left|down|up|right|next|prev)
                   OR: move-node-to-monitor [-h|--help] [--window-id <window-id>] [--focus-follows-window]
                                            [--fail-if-noop] [--] <monitor-pattern>...
                """
            case .moveNodeToWorkspace:
                """
                USAGE: move-node-to-workspace [-h|--help] [--focus-follows-window] [--wrap-around]
                                              [--stdin|--no-stdin]
                                              (next|prev)
                   OR: move-node-to-workspace [-h|--help] [--focus-follows-window] [--fail-if-noop]
                                              [--window-id <window-id>] [--] <workspace-name>
                """
            case .moveWorkspaceToMonitor:
                """
                USAGE: move-workspace-to-monitor [-h|--help] [--workspace <workspace>] [--wrap-around] (left|down|up|right)
                   OR: move-workspace-to-monitor [-h|--help] [--workspace <workspace>] [--wrap-around] (next|prev)
                   OR: move-workspace-to-monitor [-h|--help] [--workspace <workspace>] [--] <monitor-pattern>...
                """
            case .move:
                """
                USAGE: move [-h|--help] [--window-id <window-id>] [--boundaries <boundary>]
                            [--boundaries-action <boundary-action>] [--fail-if-fullscreen]
                            [--fail-if-macos-native-fullscreen] (left|down|up|right)
                """
            case .reloadConfig:
                """
                USAGE: reload-config [-h|--help] [--no-gui] [--dry-run] [--warnings-as-errors]
                """
            case .resize:
                """
                USAGE: resize [-h|--help] [--window-id <window-id>] (smart|smart-opposite|width|height) [+|-]<number>
                """
            case .runCallback:
                """
                USAGE: run-callback [-h|--help] [--for-every-window|--window-id <window-id>] on-window-detected
                   OR: run-callback [-h|--help] (on-focus-changed|on-focused-monitor-changed)
                """
            case .split:
                """
                USAGE: split [-h|--help] [--window-id <window-id>] (horizontal|vertical|opposite)
                """
            case .subscribe:
                """
                USAGE: subscribe [-h|--help] [--all] [--no-send-initial] [<event>...]
                """
            case .summonWorkspace:
                """
                USAGE: summon-workspace [-h|--help] [--fail-if-noop] [--] <workspace>
                """
            case .swap:
                """
                USAGE: swap [-h|--help] [--window-id <window-id>] [--swap-focus]
                            [--wrap-around] (left|down|up|right|dfs-next|dfs-prev)
                """
            case .testNot:
                """
                USAGE: test-not [-h|--help] <lhs> = <rhs>
                   OR: test-not [-h|--help] <lhs> ~= <rhs>
                """
            case .test:
                """
                USAGE: test [-h|--help] <lhs> = <rhs>
                   OR: test [-h|--help] <lhs> ~= <rhs>
                """
            case .triggerBinding:
                """
                USAGE: trigger-binding [-h|--help] --mode <mode-id> [--] <binding>
                """
            case ._true:
                """
                USAGE: true [-h|--help]
                """
            case .volume:
                """
                USAGE: volume [-h|--help] (up|down) [--no-gui]
                   OR: volume [-h|--help] (mute-toggle|mute-off|mute-on) [--no-gui]
                   OR: volume [-h|--help] set <number> [--no-gui]
                """
            case .workspaceBackAndForth:
                """
                USAGE: workspace-back-and-forth [-h|--help]
                """
            case .workspace:
                """
                USAGE: workspace [-h|--help] [--auto-back-and-forth] [--fail-if-noop] [--] <workspace-name>
                   OR: workspace [-h|--help] [--wrap-around] [--stdin|--no-stdin] (next|prev)
                """
        }
    }

    /// One-line description in the `aerospace --help` subcommand list
    public var purpose: String {
        switch self {
            case .balanceSizes: "Balance sizes of all windows in the current workspace"
            case .closeAllWindowsButCurrent: "On the focused workspace, close all windows but current"
            case .close: "Close the focused window"
            case .config: "Query AeroSpace config options"
            case .debugWindows: "Interactive command to record Accessibility API debug information to create bug reports"
            case .echo: "Print arguments and interpolation variables to stdout"
            case .enable: "Temporarily disable window management"
            case .eval: "Send multiple commands to AeroSpace at once"
            case .execAndForget: "Run /bin/bash -c '<bash-script>'"
            case ._false: "Return false value"
            case .flattenWorkspaceTree: "Flatten the tree of the focused workspace"
            case .focusBackAndForth: "Switch between the current and previously focused elements back and forth"
            case .focusMonitor: "Focus monitor by relative direction, by order, or by pattern"
            case .focus: "Set focus to a window."
            case .fullscreen: "Toggle the fullscreen mode for the focused window"
            case .joinWith: "Put the focused window and the nearest node in the specified direction under a common parent container"
            case .layout: "Change layout of the focused node to the given layout"
            case .listApps: "Print the list of running applications that appears in the Dock and may have a user interface"
            case .listExecEnvVars: "List environment variables that exec-* commands and callbacks are run with"
            case .listModes: "Print a list of modes currently specified in the configuration"
            case .listMonitors: "Print monitors that satisfy conditions"
            case .listWindows: "Print windows that satisfy conditions"
            case .listWorkspaces: "Print workspaces that satisfy conditions"
            case .macosNativeFullscreen: "Toggle macOS fullscreen for the focused window"
            case .macosNativeMinimize: "Minimize focused window"
            case .mode: "Activate the specified binding mode"
            case .moveMouse: "Move mouse to the requested position"
            case .moveNodeToMonitor: "Move window to monitor targeted by relative direction, by order, or by pattern"
            case .moveNodeToWorkspace: "Move the focused window to the specified workspace"
            case .moveWorkspaceToMonitor: "Move workspace to monitor targeted by relative direction, by order, or by pattern."
            case .move: "Move the focused window in the given direction"
            case .reloadConfig: "Reload currently active config"
            case .resize: "Resize the focused window"
            case .runCallback: "Run AeroSpace config callbacks on demand"
            case .split: "Split focused window"
            case .subscribe: "Subscribe to AeroSpace events and receive notifications via socket"
            case .summonWorkspace: "Move the requested workspace to the focused monitor."
            case .swap: "Swaps the focused window with another window."
            case .testNot: "Negative condition evaluation utility"
            case .test: "Condition evaluation utility"
            case .triggerBinding: "Trigger AeroSpace binding as if it was pressed by user"
            case ._true: "Return true value"
            case .volume: "Manipulate volume"
            case .workspaceBackAndForth: "Switch between the focused workspace and previously focused workspace back and forth"
            case .workspace: "Focus the specified workspace"
        }
    }
}
