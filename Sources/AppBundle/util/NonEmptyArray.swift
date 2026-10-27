/// An array with at least one element
nonisolated struct NonEmptyArray<Element>: Sequence {
    let first: Element
    let rest: [Element]

    init(_ first: Element, _ rest: [Element] = []) {
        self.first = first
        self.rest = rest
    }

    init?(_ array: [Element]) {
        guard let first = array.first else { return nil }
        self.init(first, Array(array.dropFirst()))
    }

    func makeIterator() -> IndexingIterator<[Element]> { ([first] + rest).makeIterator() }
}

extension NonEmptyArray: Equatable where Element: Equatable {}
extension NonEmptyArray: Sendable where Element: Sendable {}
