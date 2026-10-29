import Foundation

extension String {
    public func prefixLines(with: String) -> String {
        split(separator: "\n", omittingEmptySubsequences: false).map { with + $0 }.joined(separator: "\n")
    }

    public var singleQuoted: String { "'" + self + "'" }
    public var doubleQuoted: String { "\"" + self + "\"" }
}

extension [String] {
    public func joinTruncating(separator: String, length maxLength: Int, trailing: String = "…") -> String {
        if isEmpty {
            return ""
        }
        var result: String = first.orDie()
        if result.count > maxLength {
            return result.prefix(maxLength) + trailing
        }
        var remainingLen = maxLength - result.count
        let separatorCount = separator.count
        for _elem in self.dropFirst() {
            let elemCount = separatorCount + _elem.count
            if remainingLen < elemCount / 2 {
                return result + separator + trailing
            }
            let elem = separator + _elem
            if elemCount <= remainingLen {
                result += elem
                remainingLen -= elemCount
            } else {
                return result + elem.prefix(remainingLen) + trailing
            }
        }
        return result
    }
}

extension [[String]] {
    public func toPaddingTable(columnSeparator: String = " | ") -> [String] {
        let pads: [Int] = transposed().map { column in column.map { $0.count }.max().orDie() }
        return self.map { (row: [String]) in
            zip(row.enumerated(), pads)
                .map { (elem: (Int, String), pad: Int) in
                    elem.0 != row.count - 1 ? elem.1 + String(repeating: " ", count: pad - elem.1.count) : elem.1
                }
                .joined(separator: columnSeparator)
        }
    }
}
