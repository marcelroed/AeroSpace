@testable import AppBundle
import Common
import Foundation
import Testing

@Suite
struct CommonUtilTest {
    @Test
    func testToLogicalSegments() {
        expectEqual("".toLogicalSegments(), [])
        expectEqual("abc".toLogicalSegments(), [.string("abc")])
        expectEqual("123".toLogicalSegments(), [.number(123)])
        expectEqual("007".toLogicalSegments(), [.number(7)])
        expectEqual("a1b22c".toLogicalSegments(), [.string("a"), .number(1), .string("b"), .number(22), .string("c")])
        expectEqual("10abc".toLogicalSegments(), [.number(10), .string("abc")])
        expectEqual("1.5".toLogicalSegments(), [.number(1), .string("."), .number(5)])
        expectEqual("-5".toLogicalSegments(), [.string("-"), .number(5)])
        expectEqual("99999999999999999999".toLogicalSegments(), [.string("99999999999999999999")]) // Int overflow
        // Only ASCII digits are numbers
        expectEqual("١٢".toLogicalSegments(), [.string("١٢")]) // Arabic-Indic
        expectEqual("１２".toLogicalSegments(), [.string("１２")]) // Fullwidth
        expectEqual("x²".toLogicalSegments(), [.string("x²")])
        expectEqual("1\u{20E3}2".toLogicalSegments(), [.string("1\u{20E3}"), .number(2)]) // Keycap grapheme isn't a digit
    }

    @Test
    func testLogicalSegmentsOrder() {
        func less(_ a: String, _ b: String) -> Bool { a.toLogicalSegments() < b.toLogicalSegments() }
        #expect(less("a2", "a10"))
        #expect(!less("a10", "a2"))
        #expect(less("a", "a1"))
        #expect(!less("a1", "a"))
        #expect(!less("a1", "a1"))
        #expect(!less("", ""))
        #expect(less("", "a"))
        #expect(less("1", "a"))
        #expect(!less("a", "1"))
        #expect(less("a", "b"))
        #expect(!less("b", "a1"))
        expectEqual(
            ["10", "9", "a", "1", "b2", "b10", "b", "", "a1b"].sorted(by: less),
            ["", "1", "9", "10", "a", "a1b", "b", "b2", "b10"],
        )
    }

    @Test
    func testInterpolationTokens() {
        func tokens(_ str: String) -> Result<[FormatToken], CmdParseError> {
            Result { () throws(CmdParseError) in try parseFormat(str) }
        }
        expectEqual(tokens(""), .success([]))
        expectEqual(
            tokens("id: %{window-id}%{newline}%%{app-name}%"),
            .success([
                .literal("id: "),
                .interVar(.windowId),
                .interVar(.newline),
                .literal("%"),
                .interVar(.appName),
                .literal("%"),
            ]),
        )
        expectEqual(tokens("%{foo} %{bar}"), .failure("Can't parse 'foo'.\nPossible values: \(FormatVar.unionLiteral)"))
        expectEqual(tokens("%{window-id} %{foo"), .failure("Unbalanced curly braces"))
    }

    @Test
    func testGetOrNilAtIndex() {
        expectEqual([10, 20].getOrNil(atIndex: 1), 20)
        expectEqual([10, 20].getOrNil(atIndex: 2), nil)
        expectEqual([10, 20].getOrNil(atIndex: -1), nil)
        let slice = [10, 20, 30][1...] // Indices 1 and 2
        expectEqual(slice.getOrNil(atIndex: 1), 20)
        expectEqual(slice.getOrNil(atIndex: 0), nil)
        expectEqual(slice.getOrNil(atIndex: 3), nil)
    }

    @Test
    func testTransposed() {
        expectEqual([[Int]]().transposed(), [])
        expectEqual([[1]].transposed(), [[1]])
        expectEqual([[1, 2, 3], [4, 5, 6]].transposed(), [[1, 4], [2, 5], [3, 6]])
        expectEqual([[Int]]([[], []]).transposed(), [])
    }

    @Test
    func testToPaddingTable() {
        expectEqual([[String]]().toPaddingTable(), [])
        expectEqual(
            [["a", "bb", "c"], ["ddd", "e", "ff"]].toPaddingTable(),
            ["a   | bb | c", "ddd | e  | ff"],
        )
        expectEqual(
            [["a", "b"], ["cc", "d"]].toPaddingTable(columnSeparator: "   "),
            ["a    b", "cc   d"],
        )
        // Characters made of several UTF-16 code units (a combining accent, emoji) are padded by Character count
        expectEqual(
            [["e\u{301}", "x"], ["🙂🙂", "y"], ["abc", "z"]].toPaddingTable(),
            ["e\u{301}   | x", "🙂🙂  | y", "abc | z"],
        )
    }

    @Test
    func testJoinTruncating() {
        let arr = ["aaa", "bbb", "ccc"] // "aaa, bbb, ccc" is 13 characters long
        #expect([String]().joinTruncating(separator: ", ", length: 0).isEmpty)
        expectEqual(["a"].joinTruncating(separator: ", ", length: 1), "a")
        expectEqual(["abc"].joinTruncating(separator: ", ", length: 2), "ab…") // The first element counts too
        expectEqual(arr.joinTruncating(separator: ", ", length: 100), "aaa, bbb, ccc")
        expectEqual(arr.joinTruncating(separator: ", ", length: 13), "aaa, bbb, ccc") // Fits exactly: no ellipsis
        expectEqual(arr.joinTruncating(separator: ", ", length: 12), "aaa, bbb, cc…")
        expectEqual(arr.joinTruncating(separator: ", ", length: 10), "aaa, bbb, …")
        expectEqual(arr.joinTruncating(separator: ", ", length: 8), "aaa, bbb, …")
        expectEqual(arr.joinTruncating(separator: ", ", length: 6), "aaa, b…")
        expectEqual(arr.joinTruncating(separator: ", ", length: 5), "aaa, …")
        expectEqual(arr.joinTruncating(separator: ", ", length: 4), "aaa, …")
        expectEqual(arr.joinTruncating(separator: ", ", length: 1), "a…")
        expectEqual(["aaa", "bbb"].joinTruncating(separator: ", ", length: 8), "aaa, bbb") // Fits exactly: no ellipsis
        expectEqual(["x", "yyyy"].joinTruncating(separator: "|", length: 2, trailing: "..."), "x|...")
        expectEqual(["x", "yyyy"].joinTruncating(separator: "|", length: 4, trailing: "..."), "x|yy...")
    }

    @Test
    func testPrefixLines() {
        expectEqual("a\n\nb".prefixLines(with: "> "), "> a\n> \n> b")
        expectEqual("a\n".prefixLines(with: "> "), "> a\n> ")
        expectEqual("".prefixLines(with: "> "), "> ")
    }

    @Test
    func testSortedEntries() {
        let entries = ["b": 2, "a": 1, "c": 3].sortedEntries
        expectEqual(entries.map(\.key), ["a", "b", "c"])
        expectEqual(entries.map(\.value), [1, 2, 3])
        expectEqual([String: Int]().sortedEntries.map(\.key), [])
    }

    @Test
    func testWithIndex() {
        expectEqual(["a", "b", "c"].withIndex.map { "\($0.index)\($0.value)" }, ["0a", "1b", "2c"])
        expectEqual([String]().withIndex.count, 0)
    }

    @Test
    func testFilterIsInstance() {
        let mixed: [Any] = [1, "a", 2.0, "b", 3]
        expectEqual(mixed.filterIsInstance(of: String.self), ["a", "b"])
        expectEqual(mixed.filterIsInstance(of: Int.self), [1, 3])
        let objects: [AnyObject] = [Base(), Derived(), Base()]
        expectEqual(objects.filterIsInstance(of: Base.self).count, 3)
        expectEqual(objects.filterIsInstance(of: Derived.self).count, 1)
    }

    @Test
    func testSequenceHelpers() {
        expectEqual([1.5, 2.5].sum { $0 * 2 }, 8.0)
        expectEqual([Double]().sum { $0 }, 0.0)
        expectEqual([1, 2, 3].sum { $0 * 10 }, 60)
        expectEqual([1, 2, 3].singleOrNil(where: { $0 > 2 }), 3)
        expectEqual([1, 2, 3].singleOrNil(where: { $0 > 1 }), nil)
        expectEqual([1, 2, 3].singleOrNil(where: { $0 > 3 }), nil)
    }

    @Test
    func testEncodeToString() {
        expectEqual(JSONEncoder.aeroSpaceDefault.encodeToString(["b": 1, "a": 2]), "{\n  \"a\" : 2,\n  \"b\" : 1\n}")
        expectEqual(JSONEncoder.aeroSpaceDefault.encodeToString("a/b"), "\"a/b\"")
    }
}

nonisolated private class Base {}
nonisolated private final class Derived: Base {}
