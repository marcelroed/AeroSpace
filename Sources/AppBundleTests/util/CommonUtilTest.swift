@testable import AppBundle
import Common
import Testing

@Suite
struct CommonUtilTest {
    @Test
    func testToLogicalSegments() {
        let segments: [(String, StringLogicalSegments)] = [
            ("", []),
            ("abc", [.string("abc")]),
            ("007", [.number(7)]),
            ("a1b22c", [.string("a"), .number(1), .string("b"), .number(22), .string("c")]),
            ("1.5", [.number(1), .string("."), .number(5)]),
            ("-5", [.string("-"), .number(5)]),
            ("99999999999999999999", [.string("99999999999999999999")]), // Too big for an Int
            // Only ASCII digits are numbers
            ("١٢", [.string("١٢")]), // Arabic-Indic
            ("１２", [.string("１２")]), // Fullwidth
            ("x²", [.string("x²")]),
            ("1\u{20E3}2", [.string("1\u{20E3}"), .number(2)]), // A keycap grapheme isn't a digit
        ]
        for (raw, expected) in segments {
            expectEqual(raw.toLogicalSegments(), expected, "\(raw)")
        }
        // Workspaces sort by their segments: numbers by value, and before letters
        expectEqual(
            ["10", "9", "a", "1", "b2", "b10", "b", "", "a1b", "a10", "a2"].sorted { $0.toLogicalSegments() < $1.toLogicalSegments() },
            ["", "1", "9", "10", "a", "a1b", "a2", "a10", "b", "b2", "b10"],
        )
        #expect(!("a1".toLogicalSegments() < "a1".toLogicalSegments()))
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

    @Test(arguments: [
        ([], 0, "…", ""),
        (["aaa", "bbb", "ccc"], 13, "…", "aaa, bbb, ccc"), // Fits exactly: no ellipsis
        (["aaa", "bbb", "ccc"], 12, "…", "aaa, bbb, cc…"),
        (["aaa", "bbb", "ccc"], 8, "…", "aaa, bbb, …"),
        (["aaa", "bbb", "ccc"], 1, "…", "a…"), // The first element is cut too
        (["x", "yyyy"], 4, "...", "x, y..."),
    ] as [([String], Int, String, String)])
    func testJoinTruncating(elements: [String], length: Int, trailing: String, expected: String) {
        expectEqual(elements.joinTruncating(separator: ", ", length: length, trailing: trailing), expected)
    }

    /// `withIndex` (SequenceEx.swift) has no other user: delete both together
    @Test
    func testWithIndex() {
        expectEqual(["a", "b"].withIndex.map { "\($0.index)\($0.value)" }, ["0a", "1b"])
    }
}
