extension Sequence {
    @inlinable public func filterIsInstance<R>(of _: R.Type) -> [R] { compactMap { $0 as? R } }

    @inlinable public func sortedBy(_ selector: (Self.Element) -> some Comparable) -> [Self.Element] {
        sorted(by: { a, b in selector(a) < selector(b) })
    }

    @inlinable public func sortedBy(_ selectors: [(Self.Element) -> some Comparable]) -> [Self.Element] {
        sorted(by: { a, b in
            for selector in selectors {
                let a = selector(a)
                let b = selector(b)
                if a < b { return true }
                if a > b { return false }
            }
            return false
        })
    }

    @inlinable public func sum<N: AdditiveArithmetic>(_ selector: (Self.Element) -> N) -> N {
        var result = N.zero
        for elem in self {
            result += selector(elem)
        }
        return result
    }

    public var withIndex: [(index: Int, value: Element)] { enumerated().map { (index: $0.offset, value: $0.element) } }

    public func toSet() -> Set<Element> where Element: Hashable { Set(self) }
}
