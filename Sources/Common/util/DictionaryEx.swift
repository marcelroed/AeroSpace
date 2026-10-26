extension Dictionary where Key: Comparable {
    public var sortedEntries: [(key: Key, value: Value)] {
        sorted { $0.key < $1.key }
    }
}
