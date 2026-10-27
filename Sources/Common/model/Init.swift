import Synchronization

/// The server's handler, installed once at startup. nil in the CLI and in tests
public var terminationHandler: (any TerminationHandler)? { _terminationHandler.withLock { $0 } }
private let _terminationHandler = Mutex<(any TerminationHandler)?>(nil)

public func installTerminationHandler(_ handler: any TerminationHandler) {
    let wasInstalled = _terminationHandler.withLock { current in
        let wasInstalled = current != nil
        current = handler
        return wasInstalled
    }
    check(!wasInstalled, "The termination handler is installed twice") // Outside the lock: dieT reads the handler
}

public protocol TerminationHandler: Sendable {
    /// On the dying thread, which can be any thread (a die), or on main (quitting)
    func beforeTermination()
}
