@testable import AppBundle
import Common
import Testing

@Suite
struct SubcommandHelpTest: AeroSpaceTestSuite {
    @Test
    func testEverySubcommandIsCovered() {
        let expected = Set(CmdKind.allCases.map(\.rawValue)).subtracting(["exec-and-forget"]).union(["move-through", "move-workspace-to-display"])
        assertEquals(Set(expectedHelp.map(\.subcommand)), expected)
    }

    @Test(arguments: expectedHelp)
    func testHelp(subcommand: String, help: String) {
        for flag in ["--help", "-h"] {
            assertEquals(parseCommand("\(subcommand) \(flag)").helpOrNil, help)
            assertEquals(parseCmdArgs([subcommand, flag].slice).helpOrNil, help)
        }
    }

    @Test
    func testExecAndForgetHelp() {
        // The server shell treats everything after exec-and-forget as a bash script, the CLI doesn't know the subcommand
        assertEquals(parsedArgs("exec-and-forget --help", as: ExecAndForgetCmdArgs.self)?.description, "exec-and-forget  --help")
        assertEquals(parsedArgs("exec-and-forget -h", as: ExecAndForgetCmdArgs.self)?.description, "exec-and-forget  -h")
        assertEquals(parseCmdArgs(["exec-and-forget", "--help"].slice).errorOrNil, "Unrecognized subcommand 'exec-and-forget'")
        assertEquals(
            parseCommand("exec-and-forget --help", allowExecAndForget: false, allowEval: true).errorOrNil,
            "Unrecognized subcommand 'exec-and-forget'",
        )
    }

    @Test
    func testDeprecatedMoveWorkspaceToDisplaySkipsWrapAroundCheck() {
        assertEquals(parsedArgs("move-workspace-to-display --wrap-around main", as: MoveWorkspaceToMonitorCmdArgs.self)?.wrapAround, true)
        assertEquals(parseCommand("move-workspace-to-monitor --wrap-around main").errorOrNil, "--wrap-around is incompatible with <monitor-pattern> argument")
    }
}

extension ParsedCmd {
    fileprivate var helpOrNil: String? {
        switch self {
            case .help(let help): help
            case .cmd, .failure: nil
        }
    }
}

private let expectedHelp: [(subcommand: String, help: String)] = [
    ("balance-sizes", "USAGE: balance-sizes [-h|--help] [--workspace <workspace>]"),
    ("close", "USAGE: close [-h|--help] [--quit-if-last-window] [--window-id <window-id>]"),
    ("close-all-windows-but-current", "USAGE: close-all-windows-but-current [-h|--help] [--quit-if-last-window]"),
    (
        "config",
        """
        USAGE: config [-h|--help] --get <name> [--json] [--keys]
           OR: config [-h|--help] --major-keys
           OR: config [-h|--help] --all-keys
           OR: config [-h|--help] --config-path
        """,
    ),
    ("debug-windows", "USAGE: debug-windows [-h|--help] [--window-id <window-id>]"),
    ("echo", "USAGE: echo [-h|--help] [--stderr] [--window-id <window-id>] -- <string>..."),
    (
        "enable",
        """
        USAGE: enable [-h|--help] toggle
           OR: enable [-h|--help] on [--fail-if-noop]
           OR: enable [-h|--help] off [--fail-if-noop]
        """,
    ),
    ("eval", "USAGE: eval [-h|--help] [--stdin] [--] <aerospace-shell-expr>"),
    ("false", "USAGE: false [-h|--help]"),
    ("flatten-workspace-tree", "USAGE: flatten-workspace-tree [-h|--help] [--workspace <workspace>]"),
    (
        "focus",
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
        """,
    ),
    ("focus-back-and-forth", "USAGE: focus-back-and-forth [-h|--help]"),
    (
        "focus-monitor",
        """
        USAGE: focus-monitor [-h|--help] [--wrap-around] (left|down|up|right)
           OR: focus-monitor [-h|--help] [--wrap-around] (next|prev)
           OR: focus-monitor [-h|--help] [--] <monitor-pattern>...
        """,
    ),
    (
        "fullscreen",
        """
        USAGE: fullscreen [-h|--help]     [--window-id <window-id>] [--no-outer-gaps]
           OR: fullscreen [-h|--help] on  [--window-id <window-id>] [--no-outer-gaps] [--fail-if-noop]
           OR: fullscreen [-h|--help] off [--window-id <window-id>] [--fail-if-noop]
        """,
    ),
    ("join-with", "USAGE: join-with [-h|--help] [--window-id <window-id>] (left|down|up|right)"),
    (
        "layout",
        """
        USAGE: layout [-h|--help] [--window-id <window-id>|--workspace <workspace>]
                      [--root] [--fail-if-noop]
                      (<target-layout>)...
           OR: layout [-h|--help] --for-next-detected-window (tiling|floating)
        """,
    ),
    ("list-apps", "USAGE: list-apps [-h|--help] [--macos-native-hidden [no]] [--format <output-format>] [--count] [--json]"),
    ("list-exec-env-vars", "USAGE: list-exec-env-vars [-h|--help]"),
    ("list-modes", "USAGE: list-modes [-h|--help] [--current] [--count] [--json]"),
    ("list-monitors", "USAGE: list-monitors [-h|--help] [--focused [no]] [--mouse [no]] [--format <output-format>] [--count] [--json]"),
    (
        "list-windows",
        """
        USAGE: list-windows [-h|--help] (--workspace <workspace>...|--monitor <monitor>...)
                            [--monitor <monitor>...] [--workspace <workspace>...]
                            [--pid <pid>] [--app-bundle-id <app-bundle-id>] [--format <output-format>]
                            [--count] [--json]
           OR: list-windows [-h|--help] --all [--format <output-format>] [--count] [--json]
           OR: list-windows [-h|--help] --focused [--format <output-format>] [--count] [--json]
        """,
    ),
    (
        "list-workspaces",
        """
        USAGE: list-workspaces [-h|--help] --monitor <monitor>... [--visible [no]] [--empty [no]] [--format <output-format>] [--count] [--json]
           OR: list-workspaces [-h|--help] --all [--format <output-format>] [--count] [--json]
           OR: list-workspaces [-h|--help] --focused [--format <output-format>] [--count] [--json]
        """,
    ),
    (
        "macos-native-fullscreen",
        """
        USAGE: macos-native-fullscreen [-h|--help] [--window-id <window-id>]
           OR: macos-native-fullscreen [-h|--help] [--window-id <window-id>] [--fail-if-noop] on
           OR: macos-native-fullscreen [-h|--help] [--window-id <window-id>] [--fail-if-noop] off
        """,
    ),
    ("macos-native-minimize", "USAGE: macos-native-minimize [-h|--help] [--window-id <window-id>]"),
    ("mode", "USAGE: mode [-h|--help] [--] <binding-mode>"),
    (
        "move",
        """
        USAGE: move [-h|--help] [--window-id <window-id>] [--boundaries <boundary>]
                    [--boundaries-action <boundary-action>] [--fail-if-fullscreen]
                    [--fail-if-macos-native-fullscreen] (left|down|up|right)
        """,
    ),
    ("move-mouse", "USAGE: move-mouse [-h|--help] [--fail-if-noop] <mouse-position>"),
    (
        "move-node-to-monitor",
        """
        USAGE: move-node-to-monitor [-h|--help] [--window-id <window-id>] [--focus-follows-window]
                                    [--wrap-around] (left|down|up|right|next|prev)
           OR: move-node-to-monitor [-h|--help] [--window-id <window-id>] [--focus-follows-window]
                                    [--fail-if-noop] [--] <monitor-pattern>...
        """,
    ),
    (
        "move-node-to-workspace",
        """
        USAGE: move-node-to-workspace [-h|--help] [--focus-follows-window] [--wrap-around]
                                      [--stdin|--no-stdin]
                                      (next|prev)
           OR: move-node-to-workspace [-h|--help] [--focus-follows-window] [--fail-if-noop]
                                      [--window-id <window-id>] [--] <workspace-name>
        """,
    ),
    (
        "move-through", // Deprecated alias of move
        """
        USAGE: move [-h|--help] [--window-id <window-id>] [--boundaries <boundary>]
                    [--boundaries-action <boundary-action>] [--fail-if-fullscreen]
                    [--fail-if-macos-native-fullscreen] (left|down|up|right)
        """,
    ),
    (
        "move-workspace-to-display", // Deprecated alias of move-workspace-to-monitor
        """
        USAGE: move-workspace-to-monitor [-h|--help] [--workspace <workspace>] [--wrap-around] (left|down|up|right)
           OR: move-workspace-to-monitor [-h|--help] [--workspace <workspace>] [--wrap-around] (next|prev)
           OR: move-workspace-to-monitor [-h|--help] [--workspace <workspace>] [--] <monitor-pattern>...
        """,
    ),
    (
        "move-workspace-to-monitor",
        """
        USAGE: move-workspace-to-monitor [-h|--help] [--workspace <workspace>] [--wrap-around] (left|down|up|right)
           OR: move-workspace-to-monitor [-h|--help] [--workspace <workspace>] [--wrap-around] (next|prev)
           OR: move-workspace-to-monitor [-h|--help] [--workspace <workspace>] [--] <monitor-pattern>...
        """,
    ),
    ("reload-config", "USAGE: reload-config [-h|--help] [--no-gui] [--dry-run] [--warnings-as-errors]"),
    ("resize", "USAGE: resize [-h|--help] [--window-id <window-id>] (smart|smart-opposite|width|height) [+|-]<number>"),
    (
        "run-callback",
        """
        USAGE: run-callback [-h|--help] [--for-every-window|--window-id <window-id>] on-window-detected
           OR: run-callback [-h|--help] (on-focus-changed|on-focused-monitor-changed)
        """,
    ),
    ("split", "USAGE: split [-h|--help] [--window-id <window-id>] (horizontal|vertical|opposite)"),
    ("subscribe", "USAGE: subscribe [-h|--help] [--all] [--no-send-initial] [<event>...]"),
    ("summon-workspace", "USAGE: summon-workspace [-h|--help] [--fail-if-noop] [--] <workspace>"),
    (
        "swap",
        """
        USAGE: swap [-h|--help] [--window-id <window-id>] [--swap-focus]
                    [--wrap-around] (left|down|up|right|dfs-next|dfs-prev)
        """,
    ),
    (
        "test",
        """
        USAGE: test [-h|--help] <lhs> = <rhs>
           OR: test [-h|--help] <lhs> ~= <rhs>
        """,
    ),
    (
        "test-not", // Known bug: test-not prints the usage of test
        """
        USAGE: test [-h|--help] <lhs> = <rhs>
           OR: test [-h|--help] <lhs> ~= <rhs>
        """,
    ),
    ("trigger-binding", "USAGE: trigger-binding [-h|--help] --mode <mode-id> [--] <binding>"),
    ("true", "USAGE: true [-h|--help]"),
    (
        "volume",
        """
        USAGE: volume [-h|--help] (up|down) [--no-gui]
           OR: volume [-h|--help] (mute-toggle|mute-off|mute-on) [--no-gui]
           OR: volume [-h|--help] set <number> [--no-gui]
        """,
    ),
    (
        "workspace",
        """
        USAGE: workspace [-h|--help] [--auto-back-and-forth] [--fail-if-noop] [--] <workspace-name>
           OR: workspace [-h|--help] [--wrap-around] [--stdin|--no-stdin] (next|prev)
        """,
    ),
    ("workspace-back-and-forth", "USAGE: workspace-back-and-forth [-h|--help]"),
]
