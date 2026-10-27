@testable import AppBundle
import Common
import Foundation
import Testing

@Suite
struct CommonUtilTest {
    @Test
    func testToLogicalSegments() {
        #expect("".toLogicalSegments() == [])
        #expect("abc".toLogicalSegments() == [.string("abc")])
        #expect("123".toLogicalSegments() == [.number(123)])
        #expect("007".toLogicalSegments() == [.number(7)])
        #expect("a1b22c".toLogicalSegments() == [.string("a"), .number(1), .string("b"), .number(22), .string("c")])
        #expect("10abc".toLogicalSegments() == [.number(10), .string("abc")])
        #expect("1.5".toLogicalSegments() == [.number(1), .string("."), .number(5)])
        #expect("-5".toLogicalSegments() == [.string("-"), .number(5)])
        #expect("99999999999999999999".toLogicalSegments() == [.string("99999999999999999999")]) // Int overflow
        // Only ASCII digits are numbers
        #expect("١٢".toLogicalSegments() == [.string("١٢")]) // Arabic-Indic
        #expect("１２".toLogicalSegments() == [.string("１２")]) // Fullwidth
        #expect("x²".toLogicalSegments() == [.string("x²")])
        #expect("1\u{20E3}2".toLogicalSegments() == [.string("1\u{20E3}"), .number(2)]) // Keycap grapheme isn't a digit
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
        #expect(
            ["10", "9", "a", "1", "b2", "b10", "b", "", "a1b"].sorted(by: less) == ["", "1", "9", "10", "a", "a1b", "b", "b2", "b10"],
        )
    }

    @Test
    func testInterpolationTokens() {
        func tokens(_ str: String) -> Result<[FormatToken], CmdParseError> {
            Result { () throws(CmdParseError) in try parseFormat(str) }
        }
        #expect(tokens("") == .success([]))
        #expect(
            tokens("id: %{window-id}%{newline}%%{app-name}%") == .success([
                .literal("id: "),
                .interVar(.windowId),
                .interVar(.newline),
                .literal("%"),
                .interVar(.appName),
                .literal("%"),
            ]),
        )
        #expect(tokens("%{foo} %{bar}") == .failure("Can't parse 'foo'.\nPossible values: \(FormatVar.unionLiteral)"))
        #expect(tokens("%{window-id} %{foo") == .failure("Unbalanced curly braces"))
    }

    @Test
    func testTransposed() {
        #expect([[Int]]().transposed() == [])
        #expect([[1]].transposed() == [[1]])
        #expect([[1, 2, 3], [4, 5, 6]].transposed() == [[1, 4], [2, 5], [3, 6]])
        #expect([[Int]]([[], []]).transposed() == [])
    }

    @Test
    func testToPaddingTable() {
        #expect([[String]]().toPaddingTable() == [])
        #expect(
            [["a", "bb", "c"], ["ddd", "e", "ff"]].toPaddingTable() == ["a   | bb | c", "ddd | e  | ff"],
        )
        #expect(
            [["a", "b"], ["cc", "d"]].toPaddingTable(columnSeparator: "   ") == ["a    b", "cc   d"],
        )
        // Characters made of several UTF-16 code units (a combining accent, emoji) are padded by Character count
        #expect(
            [["e\u{301}", "x"], ["🙂🙂", "y"], ["abc", "z"]].toPaddingTable() == ["e\u{301}   | x", "🙂🙂  | y", "abc | z"],
        )
    }

    @Test
    func testJoinTruncating() {
        let arr = ["aaa", "bbb", "ccc"] // "aaa, bbb, ccc" is 13 characters long
        #expect([String]().joinTruncating(separator: ", ", length: 0).isEmpty)
        #expect(["a"].joinTruncating(separator: ", ", length: 1) == "a")
        #expect(["abc"].joinTruncating(separator: ", ", length: 2) == "ab…") // The first element counts too
        #expect(arr.joinTruncating(separator: ", ", length: 100) == "aaa, bbb, ccc")
        #expect(arr.joinTruncating(separator: ", ", length: 13) == "aaa, bbb, ccc") // Fits exactly: no ellipsis
        #expect(arr.joinTruncating(separator: ", ", length: 12) == "aaa, bbb, cc…")
        #expect(arr.joinTruncating(separator: ", ", length: 10) == "aaa, bbb, …")
        #expect(arr.joinTruncating(separator: ", ", length: 8) == "aaa, bbb, …")
        #expect(arr.joinTruncating(separator: ", ", length: 6) == "aaa, b…")
        #expect(arr.joinTruncating(separator: ", ", length: 5) == "aaa, …")
        #expect(arr.joinTruncating(separator: ", ", length: 4) == "aaa, …")
        #expect(arr.joinTruncating(separator: ", ", length: 1) == "a…")
        #expect(["aaa", "bbb"].joinTruncating(separator: ", ", length: 8) == "aaa, bbb") // Fits exactly: no ellipsis
        #expect(["x", "yyyy"].joinTruncating(separator: "|", length: 2, trailing: "...") == "x|...")
        #expect(["x", "yyyy"].joinTruncating(separator: "|", length: 4, trailing: "...") == "x|yy...")
    }

    @Test
    func testPrefixLines() {
        #expect("a\n\nb".prefixLines(with: "> ") == "> a\n> \n> b")
        #expect("a\n".prefixLines(with: "> ") == "> a\n> ")
        #expect("".prefixLines(with: "> ") == "> ")
    }

    @Test
    func testSortedEntries() {
        let entries = ["b": 2, "a": 1, "c": 3].sortedEntries
        #expect(entries.map(\.key) == ["a", "b", "c"])
        #expect(entries.map(\.value) == [1, 2, 3])
        #expect([String: Int]().sortedEntries.map(\.key) == [])
    }

    @Test
    func testWithIndex() {
        #expect(["a", "b", "c"].withIndex.map { "\($0.index)\($0.value)" } == ["0a", "1b", "2c"])
        #expect([String]().withIndex.count == 0)
    }

    @Test
    func testFilterIsInstance() {
        let mixed: [Any] = [1, "a", 2.0, "b", 3]
        #expect(mixed.filterIsInstance(of: String.self) == ["a", "b"])
        #expect(mixed.filterIsInstance(of: Int.self) == [1, 3])
        let objects: [AnyObject] = [Base(), Derived(), Base()]
        #expect(objects.filterIsInstance(of: Base.self).count == 3)
        #expect(objects.filterIsInstance(of: Derived.self).count == 1)
    }

    @Test
    func testSequenceHelpers() {
        #expect([1.5, 2.5].sum { $0 * 2 } == 8.0)
        #expect([Double]().sum { $0 } == 0.0)
        #expect([1, 2, 3].sum { $0 * 10 } == 60)
        #expect([1, 2, 3].singleOrNil(where: { $0 > 2 }) == 3)
        #expect([1, 2, 3].singleOrNil(where: { $0 > 1 }) == nil)
        #expect([1, 2, 3].singleOrNil(where: { $0 > 3 }) == nil)
    }

    @Test
    func testEncodeToString() {
        #expect(JSONEncoder.aeroSpaceDefault.encodeToString(["b": 1, "a": 2]) == "{\n  \"a\" : 2,\n  \"b\" : 1\n}")
        #expect(JSONEncoder.aeroSpaceDefault.encodeToString("a/b") == "\"a/b\"")
    }

    @Test
    func testCompletableFutureBlockingGetTimesOut() {
        let future = CompletableFuture<Int>()
        #expect(future.blockingGet(deadline: .now() + .milliseconds(10)) == nil)
        future.complete(42)
        #expect(future.blockingGet(deadline: .now() + .seconds(5)) == 42)
    }
}

nonisolated private class Base {}
nonisolated private final class Derived: Base {}
