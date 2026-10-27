extension Sequence {
    @inlinable public func filterIsInstance<R>(of _: R.Type) -> [R] { compactMap { $0 as? R } }

    public func mapAllOrFailure<T, E>(_ transform: (Self.Element) -> Result<T, E>) -> Result<[T], E> {
        var result: [T] = []
        for element in self {
            switch transform(element) {
                case .success(let element):
                    result.append(element)
                case .failure(let errors):
                    return .failure(errors)
            }
        }
        return .success(result)
    }

    public func mapAllOrFailure<T>(_ transform: (Self.Element) -> ParsedCmd<T>) -> ParsedCmd<[T]> {
        var result: [T] = []
        for element in self {
            switch transform(element) {
                case .cmd(let element):
                    result.append(element)
                case .help(let help):
                    return .help(help)
                case .failure(let cmdParsingFailure):
                    return .failure(cmdParsingFailure)
            }
        }
        return .cmd(result)
    }

    public func mapAllOrFailures<T, E>(_ transform: (Self.Element) -> Result<T, E>) -> Result<[T], [E]> {
        var result: [T] = []
        var errors: [E] = []
        for element in self {
            switch transform(element) {
                case .success(let element): result.append(element)
                case .failure(let error): errors.append(error)
            }
        }
        return errors.isEmpty ? .success(result) : .failure(errors)
    }

    @inlinable public func minByOrDie(_ selector: (Self.Element) -> some Comparable) -> Self.Element {
        minBy(selector) ?? dieT("Empty sequence")
    }

    @inlinable public func minBy(_ selector: (Self.Element) -> some Comparable) -> Self.Element? {
        self.min(by: { a, b in selector(a) < selector(b) })
    }

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

    public var sequencePattern: SequencePattern<Self> {
        var iterator = makeIterator()
        guard let first = iterator.next() else { return .empty }
        guard let second = iterator.next() else { return .one(first) }
        guard let _ = iterator.next() else { return .two(first, second) }
        return .many
    }
}

public enum SequencePattern<Seq: Sequence> {
    case empty
    case one(Seq.Element)
    case two(Seq.Element, Seq.Element)
    case many
}
