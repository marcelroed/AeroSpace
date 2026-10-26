// "Happy path" Optional
public enum Lateinit<T> {
    case initialized(T)
    case uninitialized

    public var val: T {
        switch self {
            case .initialized(let value): return value
            case .uninitialized: die("Property is not initialized")
        }
    }
}

extension Lateinit: Equatable where T: Equatable {}

extension Lateinit: Sendable where T: Sendable {}
