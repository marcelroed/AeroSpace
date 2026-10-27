@testable import AppBundle
import Common
import Foundation
import Testing

/// CmdKind is the single source of the help: the CLI and the server print it, and the docs repeat its synopsis and purpose
@Suite
struct SubcommandHelpTest {
    @Test(arguments: CmdKind.allCases)
    func testDocsMatchHelp(kind: CmdKind) throws {
        let adoc = try String(contentsOf: projectRoot.appending(path: "docs/aerospace-\(kind.rawValue).adoc"), encoding: .utf8)
        let lines = adoc.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        #expect(lines.contains(":manpurpose: \(kind.purpose)"))
        let start = try #require(lines.firstIndex { $0.contains("tag::synopsis") })
        let end = try #require(lines.firstIndex { $0.contains("end::synopsis") })
        var prefix = "USAGE:"
        let help = lines[start + 1 ..< end].filter { !$0.isEmpty }.map { (line: String) -> String in
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

    /// docs/ has a man page per subcommand, and the commands page includes the synopsis, the purpose and the body of each
    @Test
    func testDocsHaveAPagePerSubcommand() throws {
        let expected: Set<String> = Set(CmdKind.allCases.map { "aerospace-\($0.rawValue).adoc" })
        let pages = try FileManager.default.contentsOfDirectory(atPath: projectRoot.appending(path: "docs").path)
            .filter { $0.starts(with: "aerospace-") && $0.hasSuffix(".adoc") }
        expectEqual(Set(pages), expected)
        let commandsPage = try String(contentsOf: projectRoot.appending(path: "docs/commands.adoc"), encoding: .utf8)
        let includes = commandsPage.matches(of: /include::(?:\.\/)?(aerospace-[a-z-]+\.adoc)\[tags=([a-z]+)\]/)
        for tag in ["synopsis", "purpose", "body"] {
            let included: Set<String> = Set(includes.filter { $0.output.2 == tag }.map { String($0.output.1) })
            expectEqual(included, expected, "docs/commands.adoc, tags=\(tag)")
        }
    }

    /// `-h` and `--help` ask for the help of their own subcommand (RB-11: `test -h` printed the help of another one), in
    /// the shell of the config and in a CLI request. testDocsMatchHelp pins the text
    @Test(arguments: CmdKind.allCases.filter { $0 != .execAndForget })
    func testHelp(kind: CmdKind) {
        for flag in ["-h", "--help"] {
            expectEqual(parseCommand("\(kind.rawValue) \(flag)").failureOrNil, .help(kind), "\(flag) in the shell")
            expectEqual(parseRequestFailure([kind.rawValue, flag]), .help(kind), "\(flag) in a CLI request")
        }
    }

    @Test
    func testExecAndForgetHelp() {
        // The shell of the config treats everything after exec-and-forget as a bash script. It's not a CLI subcommand
        expectEqual(parsedCmd("exec-and-forget --help", as: ExecAndForgetCommand.self)?.description, "exec-and-forget --help")
        expectEqual(parsedCmd("exec-and-forget -h", as: ExecAndForgetCommand.self)?.description, "exec-and-forget -h")
        expectEqual(parseRequestFailure(["exec-and-forget", "--help"]), .invalid("Unrecognized subcommand 'exec-and-forget'"))
        expectEqual(
            Result { () throws(CmdParseError) in try parseShell("exec-and-forget --help", allowExecAndForget: false, allowEval: true) }.failureOrNil,
            .invalid("Unrecognized subcommand 'exec-and-forget'"),
        )
    }
}

private func parseRequestFailure(_ args: [String]) -> CmdParseError? {
    Result { () throws(CmdParseError) in try parseRequest(args) }.failureOrNil
}
