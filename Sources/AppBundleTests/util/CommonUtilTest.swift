@testable import AppBundle
import Common
import Foundation
import Testing

@Suite
struct CommonUtilTest: AeroSpaceTestSuite {
    @Test
    func testToLogicalSegments() {
        assertEquals("".toLogicalSegments(), [])
        assertEquals("abc".toLogicalSegments(), [.string("abc")])
        assertEquals("123".toLogicalSegments(), [.number(123)])
        assertEquals("007".toLogicalSegments(), [.number(7)])
        assertEquals("a1b22c".toLogicalSegments(), [.string("a"), .number(1), .string("b"), .number(22), .string("c")])
        assertEquals("10abc".toLogicalSegments(), [.number(10), .string("abc")])
        assertEquals("1.5".toLogicalSegments(), [.number(1), .string("."), .number(5)])
        assertEquals("-5".toLogicalSegments(), [.string("-"), .number(5)])
        assertEquals("99999999999999999999".toLogicalSegments(), [.string("99999999999999999999")]) // Int overflow
        // Only ASCII digits are numbers
        assertEquals("١٢".toLogicalSegments(), [.string("١٢")]) // Arabic-Indic
        assertEquals("１２".toLogicalSegments(), [.string("１２")]) // Fullwidth
        assertEquals("x²".toLogicalSegments(), [.string("x²")])
        assertEquals("1\u{20E3}2".toLogicalSegments(), [.string("1\u{20E3}"), .number(2)]) // Keycap grapheme isn't a digit
    }

    @Test
    func testLogicalSegmentsOrder() {
        func less(_ a: String, _ b: String) -> Bool { a.toLogicalSegments() < b.toLogicalSegments() }
        assertTrue(less("a2", "a10"))
        assertFalse(less("a10", "a2"))
        assertTrue(less("a", "a1"))
        assertFalse(less("a1", "a"))
        assertFalse(less("a1", "a1"))
        assertFalse(less("", ""))
        assertTrue(less("", "a"))
        assertTrue(less("1", "a"))
        assertFalse(less("a", "1"))
        assertTrue(less("a", "b"))
        assertFalse(less("b", "a1"))
        assertEquals(
            ["10", "9", "a", "1", "b2", "b10", "b", "", "a1b"].sorted(by: less),
            ["", "1", "9", "10", "a", "a1b", "b", "b2", "b10"],
        )
    }

    @Test
    func testTransposed() {
        assertEquals([[Int]]().transposed(), [])
        assertEquals([[1]].transposed(), [[1]])
        assertEquals([[1, 2, 3], [4, 5, 6]].transposed(), [[1, 4], [2, 5], [3, 6]])
        assertEquals([[Int]]([[], []]).transposed(), [])
        assertEquals([[1], [2, 3]].transposed(), [[1, 2]]) // The first row defines the column count
    }

    @Test
    func testToPaddingTable() {
        assertEquals([[String]]().toPaddingTable(), [])
        assertEquals(
            [["a", "bb", "c"], ["ddd", "e", "ff"]].toPaddingTable(),
            ["a   | bb | c", "ddd | e  | ff"],
        )
        assertEquals(
            [["a", "b"], ["cc", "d"]].toPaddingTable(columnSeparator: "   "),
            ["a    b", "cc   d"],
        )
    }

    @Test
    func testJoinTruncating() {
        let arr = ["aaa", "bbb", "ccc"] // "aaa, bbb, ccc" is 13 characters long
        assertEquals([String]().joinTruncating(separator: ", ", length: 0), "")
        assertEquals(["a"].joinTruncating(separator: ", ", length: 1), "a")
        assertEquals(["abc"].joinTruncating(separator: ", ", length: 2), "ab…") // The first element counts too
        assertEquals(arr.joinTruncating(separator: ", ", length: 100), "aaa, bbb, ccc")
        assertEquals(arr.joinTruncating(separator: ", ", length: 13), "aaa, bbb, ccc") // Fits exactly: no ellipsis
        assertEquals(arr.joinTruncating(separator: ", ", length: 12), "aaa, bbb, cc…")
        assertEquals(arr.joinTruncating(separator: ", ", length: 10), "aaa, bbb, …")
        assertEquals(arr.joinTruncating(separator: ", ", length: 8), "aaa, bbb, …")
        assertEquals(arr.joinTruncating(separator: ", ", length: 6), "aaa, b…")
        assertEquals(arr.joinTruncating(separator: ", ", length: 5), "aaa, …")
        assertEquals(arr.joinTruncating(separator: ", ", length: 4), "aaa, …")
        assertEquals(arr.joinTruncating(separator: ", ", length: 1), "a…")
        assertEquals(["aaa", "bbb"].joinTruncating(separator: ", ", length: 8), "aaa, bbb") // Fits exactly: no ellipsis
        assertEquals(["x", "yyyy"].joinTruncating(separator: "|", length: 2, trailing: "..."), "x|...")
        assertEquals(["x", "yyyy"].joinTruncating(separator: "|", length: 4, trailing: "..."), "x|yy...")
    }

    @Test
    func testPrefixLines() {
        assertEquals("a\n\nb".prefixLines(with: "> "), "> a\n> \n> b")
        assertEquals("a\n".prefixLines(with: "> "), "> a\n> ")
        assertEquals("".prefixLines(with: "> "), "> ")
    }

    @Test
    func testArrSlice() {
        let arr = [10, 20, 30, 40]
        assertEquals(arr.slice.toArray(), arr)
        assertEquals(arr.slice(1...)?.toArray(), [20, 30, 40])
        assertEquals(arr.slice(1 ..< 3)?.toArray(), [20, 30])
        assertEquals(arr.slice(4...)?.toArray(), [])
        assertNil(arr.slice(0 ..< 5))

        let slice = arr.slice(1...).orDie()
        assertEquals(slice.count, 3)
        assertEquals(slice[0], 20)
        assertEquals(slice[2], 40)
        assertEquals(slice.first, 20)
        assertEquals(slice.getOrNil(atIndex: 2), 40)
        assertNil(slice.getOrNil(atIndex: 3))
        assertNil(slice.getOrNil(atIndex: -1))
        assertEquals(slice.map { $0 / 10 }, [2, 3, 4])
        var iterated: [Int] = []
        for elem in slice { iterated.append(elem) }
        assertEquals(iterated, [20, 30, 40])
        assertEquals(Array(slice.reversed()), [40, 30, 20])

        // Nested slices are zero-based relative to the outer slice
        assertEquals(slice.slice(1...)?.toArray(), [30, 40])
        assertEquals(slice.slice(1 ..< 2)?.toArray(), [30])
        assertEquals(slice.slice(1 ..< 2)?[0], 30)
        assertNil(slice.slice(1 ..< 4))

        let literal: ArrSlice<Int> = [1, 2]
        assertEquals(literal.toArray(), [1, 2])
    }

    @Test
    func testArrSliceEquality() {
        assertEquals([1, 2, 3].slice(1...), [9, 2, 3].slice(1...))
        assertEquals([1, 2, 3].slice(1...).orDie(), [2, 3])
        assertNotEquals([1, 2].slice, [1, 2, 3].slice)
        assertNotEquals([1, 2].slice, [1, 3].slice)
        assertEquals([1].slice(1...).orDie(), [Int]().slice)
        assertEquals([1].slice(1...).orDie(), [5, 6].slice(2...).orDie())
    }

    @Test
    func testSortedEntries() {
        let entries = ["b": 2, "a": 1, "c": 3].sortedEntries
        assertEquals(entries.map(\.key), ["a", "b", "c"])
        assertEquals(entries.map(\.value), [1, 2, 3])
        assertEquals([String: Int]().sortedEntries.map(\.key), [])
    }

    @Test
    func testWithIndex() {
        assertEquals(["a", "b", "c"].withIndex.map { "\($0.index)\($0.value)" }, ["0a", "1b", "2c"])
        assertEquals([String]().withIndex.count, 0)
    }

    @Test
    func testFilterIsInstance() {
        let mixed: [Any] = [1, "a", 2.0, "b", 3]
        assertEquals(mixed.filterIsInstance(of: String.self), ["a", "b"])
        assertEquals(mixed.filterIsInstance(of: Int.self), [1, 3])
        let objects: [AnyObject] = [Base(), Derived(), Base()]
        assertEquals(objects.filterIsInstance(of: Base.self).count, 3)
        assertEquals(objects.filterIsInstance(of: Derived.self).count, 1)
    }

    @Test
    func testFlattenOptional() {
        let some: Int?? = .some(.some(1))
        let someNil: Int?? = .some(nil)
        let none: Int?? = nil
        assertEquals(some.flattenOptional(), 1)
        assertNil(someNil.flattenOptional())
        assertNil(none.flattenOptional())
    }

    @Test
    func testSequenceHelpers() {
        assertEquals([1.5, 2.5].sumOfDouble { $0 * 2 }, 8.0)
        assertEquals([Double]().sumOfDouble { $0 }, 0.0)
        assertEquals([1, 2, 3].sumOfInt { $0 * 10 }, 60)
        assertEquals([1, 2, 3].singleOrNil(where: { $0 > 2 }), 3)
        assertNil([1, 2, 3].singleOrNil(where: { $0 > 1 }))
        assertNil([1, 2, 3].singleOrNil(where: { $0 > 3 }))
    }

    @Test
    func testEncodeToString() {
        assertEquals(JSONEncoder.aeroSpaceDefault.encodeToString(["b": 1, "a": 2]), "{\n  \"a\" : 2,\n  \"b\" : 1\n}")
        assertEquals(JSONEncoder.aeroSpaceDefault.encodeToString("a/b"), "\"a/b\"")
    }
}

private class Base {}
private final class Derived: Base {}
