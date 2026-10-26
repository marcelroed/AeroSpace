public struct ParsedCliArgs<T> {
    var value: ResOrStr<T>
    var advanceBy: Int

    public init(_ value: ResOrStr<T>, advanceBy: Int) {
        self.value = value
        self.advanceBy = advanceBy
    }

    public static func succ(_ value: T, advanceBy: Int) -> ParsedCliArgs<T> {
        .init(.success(value), advanceBy: advanceBy)
    }

    public static func fail(_ msg: String, advanceBy: Int) -> ParsedCliArgs<T> {
        .init(.failure(msg), advanceBy: advanceBy)
    }

    public func map<R>(_ mapper: (T) -> R) -> ParsedCliArgs<R> {
        .init(value.map(mapper), advanceBy: advanceBy)
    }
}
