extension Array {
    /// The table must be rectangular: all rows have the same size
    public func transposed<T>() -> [[T]] where Self.Element == [T] {
        guard let firstRow = first else { return [] }
        check(allSatisfy { $0.count == firstRow.count }, "transposed() needs a rectangular table. Row sizes: \(map(\.count))")
        return firstRow.indices.map { columnIndex in map { row in row.getOrNil(atIndex: columnIndex).orDie() } }
    }

    @inlinable public func singleOrNil(where predicate: (Self.Element) throws -> Bool) rethrows -> Self.Element? {
        var found: Self.Element? = nil
        for elem in self where try predicate(elem) {
            switch found == nil {
                case true: found = elem
                case false: return nil
            }
        }
        return found
    }
}
