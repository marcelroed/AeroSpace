@testable import AppBundle
import Common
import Testing

// todo: goes away with `ResOrStr`

nonisolated func assertSucc<T>(_ actual: Result<T, some Any>, sourceLocation: SourceLocation = #_sourceLocation) {
    if case .failure = actual {
        Issue.record(Comment(rawValue: "Expected success, got \(actual)"), sourceLocation: sourceLocation)
    }
}

nonisolated func assertSucc<T: Equatable>(_ actual: Result<T, some Any>, _ expected: T, sourceLocation: SourceLocation = #_sourceLocation) {
    switch actual {
        case .failure: Issue.record(Comment(rawValue: "Expected success, got \(actual)"), sourceLocation: sourceLocation)
        case .success(let actual): #expect(actual == expected, sourceLocation: sourceLocation)
    }
}

nonisolated func assertFail<F: Equatable>(_ actual: Result<some Any, F>, _ expected: F? = nil, sourceLocation: SourceLocation = #_sourceLocation) {
    switch actual {
        case .success: Issue.record(Comment(rawValue: "Expected failure, got \(actual)"), sourceLocation: sourceLocation)
        case .failure(let actual):
            if let expected {
                #expect(actual == expected, sourceLocation: sourceLocation)
            }
    }
}
