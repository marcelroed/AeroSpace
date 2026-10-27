@testable import AppBundle
import Common
import HotKey
import Testing

@Suite
struct KeysMapTest: AeroSpaceTestSuite {
    @Test
    func testKeyToStringIsTheInverseOfKeyNotationToKeyCode() {
        for (name, key) in keyNotationToKeyCode.sorted(by: { $0.key < $1.key }) {
            #expect(key.toString() == name)
        }
    }

    /// Pins the key names and the key codes independently of `Key.toString()`
    @Test
    func testQwertyPreset() {
        #expect(getKeysPreset(.qwerty).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.carbonKeyCode)" } == [
            "0=29", "1=18", "2=19", "3=20", "4=21", "5=23", "6=22", "7=26", "8=28", "9=25", "a=0", "b=11", "backslash=42",
            "backspace=51", "backtick=50", "c=8", "comma=43", "d=2", "down=125", "e=14", "end=119", "enter=36", "equal=24",
            "esc=53", "f=3", "f1=122", "f10=109", "f11=103", "f12=111", "f13=105", "f14=107", "f15=113", "f16=106",
            "f17=64", "f18=79", "f19=80", "f2=120", "f20=90", "f3=99", "f4=118", "f5=96", "f6=97", "f7=98", "f8=100",
            "f9=101", "forwardDelete=117", "g=5", "h=4", "home=115", "i=34", "j=38", "k=40", "keypad0=82", "keypad1=83",
            "keypad2=84", "keypad3=85", "keypad4=86", "keypad5=87", "keypad6=88", "keypad7=89", "keypad8=91", "keypad9=92",
            "keypadClear=71", "keypadDecimalMark=65", "keypadDivide=75", "keypadEnter=76", "keypadEqual=81", "keypadMinus=78",
            "keypadMultiply=67", "keypadPlus=69", "l=37", "left=123", "leftSquareBracket=33", "m=46", "minus=27",
            "n=45", "o=31", "p=35", "pageDown=121", "pageUp=116", "period=47", "q=12", "quote=39", "r=15", "right=124",
            "rightSquareBracket=30", "s=1", "sectionSign=10", "semicolon=41", "slash=44", "space=49", "t=17", "tab=48",
            "u=32", "up=126", "v=9", "w=13", "x=7", "y=16", "z=6",
        ])
    }

    /// Every preset has the same key names. dvorak and colemak differ from qwerty only in the listed keys
    /// (`name=qwertyName`: the key name maps to the key that has `qwertyName` on qwerty)
    @Test
    func testDvorakAndColemakPresets() {
        for preset in KeyMapping.Preset.allCases {
            #expect(Set(getKeysPreset(preset).keys) == Set(keyNotationToKeyCode.keys))
        }
        func differencesFromQwerty(_ preset: KeyMapping.Preset) -> [String] {
            getKeysPreset(preset).filter { $0.value != keyNotationToKeyCode[$0.key] }
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value.toString())" }
        }
        #expect(differencesFromQwerty(.dvorak) == [
            "b=n", "c=i", "comma=w", "d=h", "e=d", "equal=rightSquareBracket", "f=y", "g=u", "h=j", "i=g", "j=c",
            "k=v", "l=p", "leftSquareBracket=minus", "minus=quote", "n=l", "o=s", "p=r", "period=e", "q=x", "quote=q",
            "r=o", "rightSquareBracket=equal", "s=semicolon", "semicolon=z", "slash=leftSquareBracket", "t=k", "u=f",
            "v=period", "w=comma", "x=b", "y=t", "z=slash",
        ])
        #expect(differencesFromQwerty(.colemak) == [
            "d=g", "e=k", "f=e", "g=t", "i=l", "j=y", "k=n", "l=u", "n=j", "o=semicolon", "p=r", "r=s", "s=d", "semicolon=p",
            "t=f", "u=i", "y=o",
        ])
    }

    /// Golden: every name of every preset with its key code, and the modifier names. Pins the key tables independently
    /// of how they are built
    @Test
    func testAllPresetsGolden() {
        func dump(_ preset: KeyMapping.Preset) -> [String] {
            getKeysPreset(preset).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.carbonKeyCode)" }
        }
        #expect(dump(.qwerty) == [
            "0=29", "1=18", "2=19", "3=20", "4=21", "5=23", "6=22", "7=26", "8=28", "9=25", "a=0", "b=11", "backslash=42",
            "backspace=51", "backtick=50", "c=8", "comma=43", "d=2", "down=125", "e=14", "end=119", "enter=36", "equal=24",
            "esc=53", "f=3", "f1=122", "f10=109", "f11=103", "f12=111", "f13=105", "f14=107", "f15=113", "f16=106",
            "f17=64", "f18=79", "f19=80", "f2=120", "f20=90", "f3=99", "f4=118", "f5=96", "f6=97", "f7=98", "f8=100",
            "f9=101", "forwardDelete=117", "g=5", "h=4", "home=115", "i=34", "j=38", "k=40", "keypad0=82", "keypad1=83",
            "keypad2=84", "keypad3=85", "keypad4=86", "keypad5=87", "keypad6=88", "keypad7=89", "keypad8=91", "keypad9=92",
            "keypadClear=71", "keypadDecimalMark=65", "keypadDivide=75", "keypadEnter=76", "keypadEqual=81",
            "keypadMinus=78", "keypadMultiply=67", "keypadPlus=69", "l=37", "left=123", "leftSquareBracket=33", "m=46",
            "minus=27", "n=45", "o=31", "p=35", "pageDown=121", "pageUp=116", "period=47", "q=12", "quote=39", "r=15",
            "right=124", "rightSquareBracket=30", "s=1", "sectionSign=10", "semicolon=41", "slash=44", "space=49", "t=17",
            "tab=48", "u=32", "up=126", "v=9", "w=13", "x=7", "y=16", "z=6",
        ])
        #expect(dump(.dvorak) == [
            "0=29", "1=18", "2=19", "3=20", "4=21", "5=23", "6=22", "7=26", "8=28", "9=25", "a=0", "b=45", "backslash=42",
            "backspace=51", "backtick=50", "c=34", "comma=13", "d=4", "down=125", "e=2", "end=119", "enter=36", "equal=30",
            "esc=53", "f=16", "f1=122", "f10=109", "f11=103", "f12=111", "f13=105", "f14=107", "f15=113", "f16=106",
            "f17=64", "f18=79", "f19=80", "f2=120", "f20=90", "f3=99", "f4=118", "f5=96", "f6=97", "f7=98", "f8=100",
            "f9=101", "forwardDelete=117", "g=32", "h=38", "home=115", "i=5", "j=8", "k=9", "keypad0=82", "keypad1=83",
            "keypad2=84", "keypad3=85", "keypad4=86", "keypad5=87", "keypad6=88", "keypad7=89", "keypad8=91", "keypad9=92",
            "keypadClear=71", "keypadDecimalMark=65", "keypadDivide=75", "keypadEnter=76", "keypadEqual=81",
            "keypadMinus=78", "keypadMultiply=67", "keypadPlus=69", "l=35", "left=123", "leftSquareBracket=27", "m=46",
            "minus=39", "n=37", "o=1", "p=15", "pageDown=121", "pageUp=116", "period=14", "q=7", "quote=12", "r=31",
            "right=124", "rightSquareBracket=24", "s=41", "sectionSign=10", "semicolon=6", "slash=33", "space=49", "t=40",
            "tab=48", "u=3", "up=126", "v=47", "w=43", "x=11", "y=17", "z=44",
        ])
        #expect(dump(.colemak) == [
            "0=29", "1=18", "2=19", "3=20", "4=21", "5=23", "6=22", "7=26", "8=28", "9=25", "a=0", "b=11", "backslash=42",
            "backspace=51", "backtick=50", "c=8", "comma=43", "d=5", "down=125", "e=40", "end=119", "enter=36", "equal=24",
            "esc=53", "f=14", "f1=122", "f10=109", "f11=103", "f12=111", "f13=105", "f14=107", "f15=113", "f16=106",
            "f17=64", "f18=79", "f19=80", "f2=120", "f20=90", "f3=99", "f4=118", "f5=96", "f6=97", "f7=98", "f8=100",
            "f9=101", "forwardDelete=117", "g=17", "h=4", "home=115", "i=37", "j=16", "k=45", "keypad0=82", "keypad1=83",
            "keypad2=84", "keypad3=85", "keypad4=86", "keypad5=87", "keypad6=88", "keypad7=89", "keypad8=91", "keypad9=92",
            "keypadClear=71", "keypadDecimalMark=65", "keypadDivide=75", "keypadEnter=76", "keypadEqual=81",
            "keypadMinus=78", "keypadMultiply=67", "keypadPlus=69", "l=32", "left=123", "leftSquareBracket=33", "m=46",
            "minus=27", "n=38", "o=41", "p=15", "pageDown=121", "pageUp=116", "period=47", "q=12", "quote=39", "r=1",
            "right=124", "rightSquareBracket=30", "s=2", "sectionSign=10", "semicolon=35", "slash=44", "space=49", "t=3",
            "tab=48", "u=34", "up=126", "v=9", "w=13", "x=7", "y=31", "z=6",
        ])
        #expect(modifiersMap.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.rawValue)" } == [
            "alt=524288", "cmd=1048576", "ctrl=262144", "shift=131072",
        ])
    }

    @Test
    func testBindingDescriptionWithKeyCode() {
        let result = parseConfig(
            """
            key-mapping.preset = 'dvorak'
            [mode.main.binding]
                alt-quote = 'focus left'
                cmd-shift-ctrl-alt-backtick = 'focus right'
                keypadDecimalMark = 'focus up'
            """,
        )
        #expect(result.errors == [])
        let bindings = result.config.modes[mainModeId]?.bindings.values.sorted { $0.descriptionWithKeyCode < $1.descriptionWithKeyCode } ?? []
        #expect(bindings.map(\.descriptionWithKeyCode) == ["alt-ctrl-cmd-shift-backtick", "alt-q", "keypadDecimalMark"])
        #expect(bindings.map(\.descriptionWithKeyNotation) == ["cmd-shift-ctrl-alt-backtick", "alt-quote", "keypadDecimalMark"])
    }

    @Test
    func testBindingRedeclaration() {
        let result = parseConfig(
            """
            [mode.main.binding]
                alt-shift-h = 'focus left'
                shift-alt-h = 'focus right'
            """,
        )
        #expect(result.strErrors == ["[ERROR] mode.main.binding.shift-alt-h: 'alt-shift-h' Binding redeclaration"])
        #expect(result.config.modes[mainModeId]?.bindings["alt-shift-h"]?.descriptionWithKeyNotation == "shift-alt-h")
    }

    @Test
    func testBindingRedeclarationOfDroppedBinding() {
        let result = parseConfig(
            """
            [mode.main.binding]
                alt-shift-h = 'focus left'
                shift-alt-h = 'bogus'
            """,
        )
        #expect(result.strErrors == [
            "[ERROR] mode.main.binding.shift-alt-h: 'alt-shift-h' Binding redeclaration",
            "[ERROR] mode.main.binding.shift-alt-h: Unrecognized subcommand 'bogus'",
        ])
        #expect(result.config.modes[mainModeId]?.bindings["alt-shift-h"]?.descriptionWithKeyNotation == "alt-shift-h")
    }
}
