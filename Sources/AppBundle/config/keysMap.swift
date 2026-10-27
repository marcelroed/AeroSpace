import AppKit
import Common
import HotKey

func getKeysPreset(_ layout: KeyMapping.Preset) -> [String: Key] {
    return switch layout {
        case .qwerty: keyNotationToKeyCode
        case .dvorak: dvorakMap
        case .colemak: colemakMap
    }
}

extension Key: @unchecked @retroactive Sendable {}

let keyNotationToKeyCode: [String: Key] = [
    "sectionSign": .section,
    "0": .zero,
    "1": .one,
    "2": .two,
    "3": .three,
    "4": .four,
    "5": .five,
    "6": .six,
    "7": .seven,
    "8": .eight,
    "9": .nine,
    "minus": .minus,
    "equal": .equal,

    "q": .q,
    "w": .w,
    "e": .e,
    "r": .r,
    "t": .t,
    "y": .y,
    "u": .u,
    "i": .i,
    "o": .o,
    "p": .p,
    "leftSquareBracket": .leftBracket,
    "rightSquareBracket": .rightBracket,
    "backslash": .backslash,

    "a": .a,
    "s": .s,
    "d": .d,
    "f": .f,
    "g": .g,
    "h": .h,
    "j": .j,
    "k": .k,
    "l": .l,
    "semicolon": .semicolon,
    "quote": .quote,

    "z": .z,
    "x": .x,
    "c": .c,
    "v": .v,
    "b": .b,
    "n": .n,
    "m": .m,
    "comma": .comma,
    "period": .period,
    "slash": .slash,

    "keypad0": .keypad0,
    "keypad1": .keypad1,
    "keypad2": .keypad2,
    "keypad3": .keypad3,
    "keypad4": .keypad4,
    "keypad5": .keypad5,
    "keypad6": .keypad6,
    "keypad7": .keypad7,
    "keypad8": .keypad8,
    "keypad9": .keypad9,
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

    "f1": .f1,
    "f2": .f2,
    "f3": .f3,
    "f4": .f4,
    "f5": .f5,
    "f6": .f6,
    "f7": .f7,
    "f8": .f8,
    "f9": .f9,
    "f10": .f10,
    "f11": .f11,
    "f12": .f12,
    "f13": .f13,
    "f14": .f14,
    "f15": .f15,
    "f16": .f16,
    "f17": .f17,
    "f18": .f18,
    "f19": .f19,
    "f20": .f20,

    "backtick": .grave,
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

private let dvorakMap: [String: Key] = keyNotationToKeyCode + [
    "leftSquareBracket": .minus,
    "rightSquareBracket": .equal,

    "quote": .q,
    "comma": .w,
    "period": .e,
    "p": .r,
    "y": .t,
    "f": .y,
    "g": .u,
    "c": .i,
    "r": .o,
    "l": .p,
    "slash": .leftBracket, // leftBracket -> leftSquareBracket
    "equal": .rightBracket, // rightBracket -> rightSquareBracket
    "backslash": .backslash,

    "a": .a,
    "o": .s,
    "e": .d,
    "u": .f,
    "i": .g,
    "d": .h,
    "h": .j,
    "t": .k,
    "n": .l,
    "s": .semicolon,
    "minus": .quote,

    "semicolon": .z,
    "q": .x,
    "j": .c,
    "k": .v,
    "x": .b,
    "b": .n,
    "m": .m,
    "w": .comma,
    "v": .period,
    "z": .slash,
]

private let colemakMap: [String: Key] = keyNotationToKeyCode + [
    "q": .q,
    "w": .w,
    "f": .e,
    "p": .r,
    "g": .t,
    "j": .y,
    "l": .u,
    "u": .i,
    "y": .o,
    "semicolon": .p,
    "leftSquareBracket": .leftBracket,
    "rightSquareBracket": .rightBracket,
    "backslash": .backslash,

    "a": .a,
    "r": .s,
    "s": .d,
    "t": .f,
    "d": .g,
    "h": .h,
    "n": .j,
    "e": .k,
    "i": .l,
    "o": .semicolon,
    "quote": .quote,

    "z": .z,
    "x": .x,
    "c": .c,
    "v": .v,
    "b": .b,
    "k": .n,
    "m": .m,
    "comma": .comma,
    "period": .period,
    "slash": .slash,
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
