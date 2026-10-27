import AppKit
import Common
import HotKey

extension Key: @unchecked @retroactive Sendable {}

struct KeyMapping: Equatable, Sendable {
    enum Preset: String, CaseIterable, Sendable {
        case qwerty, dvorak, colemak
    }

    init(
        preset: Preset = .qwerty,
        rawKeyNotationToKeyCode: [String: Key] = [:],
    ) {
        self.preset = preset
        self.rawKeyNotationToKeyCode = rawKeyNotationToKeyCode
    }

    fileprivate var preset: Preset = .qwerty
    fileprivate var rawKeyNotationToKeyCode: [String: Key] = [:]

    func resolve() -> [String: Key] {
        getKeysPreset(preset) + rawKeyNotationToKeyCode
    }
}

let keyMappingFields: [String: Field<KeyMapping>] = [
    "preset": Field(\.preset, decodeParsed { parseEnum($0, KeyMapping.Preset.self) }),
    "key-notation-to-key-code": Field(\.rawKeyNotationToKeyCode) { raw, path, d in
        guard let table = decodeDict(raw, path, &d) else { return nil }
        var result: [String: Key] = [:]
        for (notation, value) in table {
            guard notation.rangeOfCharacter(from: .whitespacesAndNewlines) == nil && !notation.contains("-") else {
                d.error(path, "\(notation.singleQuoted) is invalid key notation")
                continue
            }
            guard let keyCode = decodeString(value, path + .key(notation), &d) else { continue }
            switch keyNotationToKeyCode[keyCode] {
                case let key?: result[notation] = key
                case nil: d.error(path + .key(notation), "\(keyCode.singleQuoted) is invalid key code")
            }
        }
        return result
    },
]

func getKeysPreset(_ preset: KeyMapping.Preset) -> [String: Key] {
    switch preset {
        case .qwerty: keyNotationToKeyCode
        case .dvorak: dvorakKeys
        case .colemak: colemakKeys
    }
}

let keyNotationToKeyCode: [String: Key] = presetKeys(
    "minus equal q w e r t y u i o p leftSquareBracket rightSquareBracket backslash a s d f g h j k l semicolon quote " +
        "z x c v b n m comma period slash",
)
private let dvorakKeys: [String: Key] = presetKeys(
    "leftSquareBracket rightSquareBracket quote comma period p y f g c r l slash equal backslash a o e u i d h t n " +
        "s minus semicolon q j k x b m w v z",
)
private let colemakKeys: [String: Key] = presetKeys(
    "minus equal q w f p g j l u y semicolon leftSquareBracket rightSquareBracket backslash a r s t d h n e i " +
        "o quote z x c v b k m comma period slash",
)

/// The keys that the presets permute, row by row as on a qwerty keyboard. A preset names each of them
private let permutableKeys: [Key] = [
    .minus, .equal,
    .q, .w, .e, .r, .t, .y, .u, .i, .o, .p, .leftBracket, .rightBracket, .backslash,
    .a, .s, .d, .f, .g, .h, .j, .k, .l, .semicolon, .quote,
    .z, .x, .c, .v, .b, .n, .m, .comma, .period, .slash,
]

private func presetKeys(_ names: String) -> [String: Key] {
    let names = names.split(separator: " ").map(String.init)
    check(names.count == permutableKeys.count && Set(names).count == names.count)
    return sharedKeys + Dictionary(uniqueKeysWithValues: zip(names, permutableKeys))
}

/// The keys that have the same name in every preset
private let sharedKeys: [String: Key] = {
    let namedByHotKey = (0 ... 9).map { "\($0)" } + (0 ... 9).map { "keypad\($0)" } + (1 ... 20).map { "f\($0)" }
    return specialKeys + Dictionary(uniqueKeysWithValues: namedByHotKey.map { ($0, Key(string: $0).orDie()) })
}()

private let specialKeys: [String: Key] = [
    "sectionSign": .section,
    "backtick": .grave,

    "keypadClear": .keypadClear,
    "keypadDecimalMark": .keypadDecimal,
    "keypadDivide": .keypadDivide,
    "keypadEnter": .keypadEnter,
    "keypadEqual": .keypadEquals,
    "keypadMinus": .keypadMinus,
    "keypadMultiply": .keypadMultiply,
    "keypadPlus": .keypadPlus,

    "pageUp": .pageUp,
    "pageDown": .pageDown,
    "home": .home,
    "end": .end,
    "forwardDelete": .forwardDelete,

    "space": .space,
    "enter": .return,
    "esc": .escape,
    "backspace": .delete,
    "tab": .tab,

    "left": .leftArrow,
    "down": .downArrow,
    "up": .upArrow,
    "right": .rightArrow,
]

/// In the order in which `toString()` lists the modifiers
private let modifierNames: [(name: String, flag: NSEvent.ModifierFlags)] = [("alt", .option), ("ctrl", .control), ("cmd", .command), ("shift", .shift)]

let modifiersMap: [String: NSEvent.ModifierFlags] = Dictionary(uniqueKeysWithValues: modifierNames)

extension NSEvent.ModifierFlags {
    func toString() -> String { modifierNames.filter { contains($0.flag) }.map(\.name).joined(separator: "-") }
}

private let keyCodeToKeyNotation: [Key: String] = Dictionary(uniqueKeysWithValues: keyNotationToKeyCode.map { ($0.value, $0.key) })

extension Key {
    /// The inverse of `keyNotationToKeyCode`. Bindings only contain keys from that table (the presets and the values of
    /// 'key-notation-to-key-code' come from it)
    func toString() -> String { keyCodeToKeyNotation[self].orDie() }
}
