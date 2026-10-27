import AppKit
import Common
import HotKey

struct Mode: Equatable, Sendable {
    var bindings: [String: HotkeyBinding]

    static let zero = Mode(bindings: [:])
}

struct HotkeyBinding: Equatable, Sendable {
    let modifiers: NSEvent.ModifierFlags
    let keyCode: Key
    let commands: Shell<any Command>
    let descriptionWithKeyCode: String
    let descriptionWithKeyNotation: String

    init(_ modifiers: NSEvent.ModifierFlags, _ keyCode: Key, _ commands: Shell<any Command>, descriptionWithKeyNotation: String) {
        self.modifiers = modifiers
        self.keyCode = keyCode
        self.commands = commands
        self.descriptionWithKeyCode = modifiers.isEmpty
            ? keyCode.toString()
            : modifiers.toString() + "-" + keyCode.toString()
        self.descriptionWithKeyNotation = descriptionWithKeyNotation
    }

    static func == (lhs: HotkeyBinding, rhs: HotkeyBinding) -> Bool {
        lhs.modifiers == rhs.modifiers &&
            lhs.keyCode == rhs.keyCode &&
            lhs.descriptionWithKeyCode == rhs.descriptionWithKeyCode &&
            lhs.commands.strictEquals(rhs.commands)
    }
}

func decodeModes(_ raw: OrderedJson, _ path: ConfigBacktrace, _ mapping: [String: Key], _ d: inout Diagnostics) -> [String: Mode] {
    guard let table = decodeDict(raw, path, &d) else { return [:] }
    let fields: [String: Field<Mode>] = ["binding": Field(\.bindings) { raw, path, d in decodeBindings(raw, path, mapping, &d) }]
    var result: [String: Mode] = [:]
    for (name, raw) in table {
        var mode = Mode.zero
        decodeTable(raw, into: &mode, fields, path + .key(name), &d)
        result[name] = mode
    }
    if !result.keys.contains(mainModeId) {
        d.error(path, "Please specify '\(mainModeId)' mode")
    }
    return result
}

/// A binding with a bad key or modifiers is dropped. A binding whose command doesn't parse is kept with the empty command
private func decodeBindings(_ raw: OrderedJson, _ path: ConfigBacktrace, _ mapping: [String: Key], _ d: inout Diagnostics) -> [String: HotkeyBinding]? {
    guard let table = decodeDict(raw, path, &d) else { return nil }
    var result: [String: HotkeyBinding] = [:]
    for (notation, rawCommand) in table {
        let path = path + .key(notation)
        guard let (modifiers, key) = parseBinding(notation, path, mapping, &d) else { continue }
        let binding = HotkeyBinding(modifiers, key, decodeShellOfCommands(rawCommand, path, &d) ?? .empty, descriptionWithKeyNotation: notation)
        if result.keys.contains(binding.descriptionWithKeyCode) {
            d.error(path, "'\(binding.descriptionWithKeyCode)' Binding redeclaration")
        }
        result[binding.descriptionWithKeyCode] = binding
    }
    return result
}

private func parseBinding(_ raw: String, _ path: ConfigBacktrace, _ mapping: [String: Key], _ d: inout Diagnostics) -> (NSEvent.ModifierFlags, Key)? {
    let parts = raw.split(separator: "-")
    let modifiers = parts.dropLast().mapAllOrFailure { modifiersMap[String($0)].toResult("Can't parse modifiers in '\(raw)' binding") }
    guard let modifiers = d.unwrap(modifiers, path) else { return nil }
    guard let key = parts.last.flatMap({ mapping[String($0)] }) else {
        d.error(path, "Can't parse the key in '\(raw)' binding")
        return nil
    }
    return (NSEvent.ModifierFlags(modifiers), key)
}
