@testable import AppBundle
import Common
import Foundation
import Testing

/// grammar/commands-bnf-grammar.txt generates the shell completion. It repeats the options of every subcommand, so it
/// must list the options of the help (CmdKind is the source of truth)
@Suite
struct CompletionGrammarTest {
    @Test(arguments: CmdKind.allCases.filter { $0 != CmdKind.execAndForget }) // The config shell only
    func grammarHasTheOptionsOfTheHelp(kind: CmdKind) throws {
        let grammar = try CompletionGrammar.load()
        let helpOptions = options(in: kind.help).subtracting(["--help"])
        expectEqual(grammar.options(of: kind.rawValue), helpOptions)
    }

    @Test
    func grammarHasNoOtherSubcommands() throws {
        let subcommands = try CompletionGrammar.load().alternatives.keys
        expectEqual(Set(subcommands), Set(CmdKind.allCases.map(\.rawValue)).subtracting(["exec-and-forget"]))
    }

    @Test
    func grammarHasTheSubscribeEvents() throws {
        let events = try #require(CompletionGrammar.load().rules["event"]).split(separator: "|")
        expectEqual(events.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }, ServerEventType.cliArgsCases)
    }
}

/// The parts of the grammar that the test checks: the alternatives of `<subcommand>` and the other rules
private struct CompletionGrammar {
    /// The subcommand → the text of its alternatives
    let alternatives: [String: [String]]
    /// The rule name, without the angle brackets → the text of the rule
    let rules: [String: String]

    static func load() throws -> Self {
        let text = try String(contentsOf: projectRoot.appending(path: "grammar/commands-bnf-grammar.txt"), encoding: .utf8)
        // Drop the comments, and the shell commands that complete values: they hold options of other subcommands
        let body = text.split(separator: "\n").filter { !$0.starts(with: "#") }.joined(separator: "\n")
            .replacing(/\{\{\{.*?\}\}\}/, with: "")
        var rules: [String: String] = [:]
        for match in body.matches(of: /<([a-z0-9_]+)> ::=(.*?);/.dotMatchesNewlines()) {
            rules[String(match.output.1)] = String(match.output.2)
        }
        var alternatives: [String: [String]] = [:]
        for line in try #require(rules["subcommand"]).split(separator: "\n") {
            let alternative = line.trimmingCharacters(in: .whitespaces).removePrefix("| ")
            guard let subcommand = alternative.split(separator: " ").first else { continue }
            alternatives[String(subcommand), default: []].append(alternative)
        }
        return Self(alternatives: alternatives, rules: rules)
    }

    /// The options of the alternatives of `subcommand`, with the rules they refer to
    func options(of subcommand: String) -> Set<String> {
        var result: Set<String> = []
        var visited: Set<String> = []
        var pending = alternatives[subcommand] ?? []
        while let text = pending.popLast() {
            result.formUnion(AppBundleTests.options(in: text))
            for match in text.matches(of: /<([a-z0-9_]+)>/) {
                let name = String(match.output.1)
                if let rule = rules[name], visited.insert(name).inserted { pending.append(rule) }
            }
        }
        return result
    }
}

private func options(in text: String) -> Set<String> {
    Set(text.matches(of: /--[a-z][a-z-]*/).map { String($0.output) })
}
