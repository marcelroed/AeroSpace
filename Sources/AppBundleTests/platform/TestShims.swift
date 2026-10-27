@testable import AppBundle

/// Tests write window ids as literals
extension WindowId: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: UInt32) { self.init(raw: value) }
}
