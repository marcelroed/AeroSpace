import Foundation

public protocol AeroAny {}

extension AeroAny {
    @discardableResult
    @inlinable
    public func apply(_ block: (Self) -> Void) -> Self {
        block(self)
        return self
    }

    @inlinable public func takeIf(_ predicate: (Self) -> Bool) -> Self? { predicate(self) ? self : nil }
    @inlinable public func then<R>(_ body: (Self) -> R) -> R { body(self) }
}

extension String: AeroAny {}
extension Array: AeroAny {}
extension URL: AeroAny {}
extension CGFloat: AeroAny {}
