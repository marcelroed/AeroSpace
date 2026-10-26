public typealias StringLogicalSegments = [StringLogicalSegment]
extension StringLogicalSegments {
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.lexicographicallyPrecedes(rhs) }
}

public enum StringLogicalSegment: Comparable, Equatable, Sendable {
    case string(String)
    case number(Int)

    public static func < (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
            case (.string(let a), .string(let b)): a < b
            case (.number(let a), .number(let b)): a < b
            case (.number, _): true
            case (.string, _): false
        }
    }
}

extension String {
    public func toLogicalSegments() -> StringLogicalSegments {
        var currentSegment: String = ""
        var isPrevNumber: Bool = false // Initial value doesn't matter
        var result: [String] = []
        for char in self {
            let isCurNumber = char.isASCII && char.isNumber
            if isCurNumber != isPrevNumber && !currentSegment.isEmpty {
                result.append(currentSegment)
                currentSegment = ""
            }
            currentSegment.append(char)
            isPrevNumber = isCurNumber
        }
        if !currentSegment.isEmpty {
            result.append(currentSegment)
        }
        return result.map { Int($0).flatMap(StringLogicalSegment.number) ?? .string($0) }
    }
}
