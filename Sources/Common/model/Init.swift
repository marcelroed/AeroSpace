import Synchronization

/// The server's handler, installed once at startup. nil in the CLI and in tests
public var terminationHandler: (any TerminationHandler)? { _terminationHandler.withLock { $0 } }
private let _terminationHandler = Mutex<(any TerminationHandler)?>(nil)

public func installTerminationHandler(_ handler: any TerminationHandler) {
    _terminationHandler.withLock { $0 = handler }
}

public protocol TerminationHandler: Sendable {
    @MainActor
    func beforeTermination()
}
