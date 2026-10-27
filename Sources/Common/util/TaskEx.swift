import Foundation
import Synchronization

// _inheritActorContext is a private attribute that comes from Task init.
// To find the original, run:
// grep -H 'public init.*operation' "$(find /Applications/Xcode.app -path '*/MacOSX*/_Concurrency.swiftmodule/arm64e-apple-macos.swiftinterface')"
//
// https://github.com/swiftlang/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md
extension Task  /*This comment breaks the regex in lint.sh*/ {
    @discardableResult
    public static func startUnstructured(
        @_inheritActorContext _ operation: sending @escaping @isolated(any) () async -> Success,
    ) -> Task<Success, Failure> where Failure == Never, Success == () {
        .init(operation: operation)
    }

    @discardableResult
    public static func startUnstructured(
        @_inheritActorContext _ operation: sending @escaping @isolated(any) () async throws -> Success,
    ) -> Task<Success, Failure> where Failure == any Error, Success == () {
        .init(operation: operation)
    }
}

/// nil if `body` doesn't finish within `seconds`. `body` can't be cancelled, so it keeps running then
public func withTimeout<T: Sendable>(seconds: Int, _ body: @escaping @Sendable () async -> T) async -> T? {
    await withCheckedContinuation { cont in
        let isDone = Mutex(false)
        let resume: @Sendable (T?) -> Void = { result in
            // Make sure to resume continuation only once
            let wasAlreadyDone = isDone.withLock { isDone in
                defer { isDone = true }
                return isDone
            }
            if !wasAlreadyDone { cont.resume(returning: result) }
        }
        Task.startUnstructured { resume(await body()) }
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(seconds)) { resume(nil) }
    }
}
