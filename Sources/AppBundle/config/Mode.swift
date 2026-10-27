import Common
import HotKey

struct Mode: Equatable, Sendable {
    var bindings: [String: HotkeyBinding]

    static let zero = Mode(bindings: [:])
}

func parseModes(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext, _ mapping: [String: Key]) -> [String: Mode] {
    guard let rawTable = parseTomlTable(raw, backtrace).getOrNil(appendErrorTo: &c.errors) else { return [:] }
    var result: [String: Mode] = [:]
    for (key, value) in rawTable {
        result[key] = parseMode(value, backtrace + .key(key), &c, mapping)
    }
    if !result.keys.contains(mainModeId) {
        c.errors.append(.init(backtrace, "Please specify '\(mainModeId)' mode"))
    }
    return result
}

func parseMode(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext, _ mapping: [String: Key]) -> Mode {
    let fields: [String: Parser<Mode>] = ["binding": Parser(\.bindings) { raw, backtrace, c in parseBindings(raw, backtrace, &c, mapping) }]
    return parseTable(raw, .zero, fields, backtrace, &c)
}
