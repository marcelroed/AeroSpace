@testable import AppBundle
import Common
import Foundation
import Testing

@Suite
struct SubcommandHelpTest {
    /// CmdKind is the source of the help; the docs repeat its synopsis and purpose
    @Test(arguments: CmdKind.allCases)
    func testDocsMatchHelp(kind: CmdKind) throws {
        let adoc = try String(contentsOf: projectRoot.appending(path: "docs/aerospace-\(kind.rawValue).adoc"), encoding: .utf8)
        let lines = adoc.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.contains(":manpurpose: \(kind.purpose)"))
        let start = try #require(lines.firstIndex { $0.contains("tag::synopsis") }) + 1
        let end = try #require(lines.firstIndex { $0.contains("end::synopsis") })
        var prefix = "USAGE:"
        let help = lines[start ..< end].filter { !$0.isEmpty }.map { line in
            let line = line.removePrefix("   ")
            guard line.starts(with: "aerospace") else { return line }
            defer { prefix = "   OR:" }
            return prefix + line.removePrefix("aerospace")
        }
        expectEqual(help.joined(separator: "\n"), kind.help)
    }

    /// The CLI reads its stdin and sends it only for these subcommands
    @Test(arguments: CmdKind.allCases)
    func testSubcommandTakesStdinWhenItsHelpSaysSo(kind: CmdKind) {
        expectEqual(kind.takesStdin, kind.help.contains("--stdin"))
    }

    @Test
    func testEveryDocsPageIsASubcommand() throws {
        let pages = try FileManager.default.contentsOfDirectory(atPath: projectRoot.appending(path: "docs").path)
            .filter { $0.starts(with: "aerospace-") && $0.hasSuffix(".adoc") }
        expectEqual(Set(pages), Set(CmdKind.allCases.map { "aerospace-\($0.rawValue).adoc" }))
    }

    @Test
    func testEverySubcommandIsCovered() {
        let expected = Set(CmdKind.allCases.map(\.rawValue)).subtracting(["exec-and-forget"])
        expectEqual(Set(expectedHelp.map(\.subcommand)), expected)
    }

    @Test(arguments: expectedHelp)
    func testHelp(subcommand: String, help: String) {
        for flag in ["--help", "-h"] {
            expectEqual(parseCommand("\(subcommand) \(flag)").helpOrNil, help)
            // The CLI answers the help itself, the server parses the args without the shell
            expectEqual(Result { () throws(CmdParseError) in try parseSubcommand([subcommand, flag]) }.failureOrNil?.message, help)
        }
    }

    @Test
    func testExecAndForgetHelp() {
        // The server shell treats everything after exec-and-forget as a bash script, the CLI doesn't know the subcommand
        expectEqual(parsedCmd("exec-and-forget --help", as: ExecAndForgetCommand.self)?.description, "exec-and-forget --help")
        expectEqual(parsedCmd("exec-and-forget -h", as: ExecAndForgetCommand.self)?.description, "exec-and-forget -h")
        expectEqual(
            Result { () throws(CmdParseError) in try parseSubcommand(["exec-and-forget", "--help"]) }.failureOrNil,
            .invalid("Unrecognized subcommand 'exec-and-forget'"),
        )
        expectEqual(
            Result { () throws(CmdParseError) in try parseShell("exec-and-forget --help", allowExecAndForget: false, allowEval: true) }.failureOrNil,
            .invalid("Unrecognized subcommand 'exec-and-forget'"),
        )
    }

    @Test
    func testMoveWorkspaceToMonitorChecksWrapAround() {
        expectEqual(parseCommand("move-workspace-to-monitor --wrap-around main").errorOrNil, "--wrap-around is incompatible with <monitor-pattern> argument")
    }

    @Test(arguments: ["move-through", "move-workspace-to-display"])
    func testDeprecatedAliasesAreGone(alias: String) {
        expectEqual(parseCommand("\(alias) --help").errorOrNil, "Unrecognized subcommand '\(alias)'")
    }
}

nonisolated private let expectedHelp: [(subcommand: String, help: String)] = [
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
    ("echo", "USAGE: echo [-h|--help] [--stderr] [--window-id <window-id>] [--] <string>..."),
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
                                      [--stdin]
                                      (next|prev)
           OR: move-node-to-workspace [-h|--help] [--focus-follows-window] [--fail-if-noop]
                                      [--window-id <window-id>] [--] <workspace-name>
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
        "test-not",
        """
        USAGE: test-not [-h|--help] <lhs> = <rhs>
           OR: test-not [-h|--help] <lhs> ~= <rhs>
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
           OR: workspace [-h|--help] [--wrap-around] [--stdin] (next|prev)
        """,
    ),
    ("workspace-back-and-forth", "USAGE: workspace-back-and-forth [-h|--help]"),
]
