@testable import AppBundle
import Common
import Testing
import XCTest

// The helpers work in both test frameworks: inside a `@Test` they report with `Issue.record`,
// and inside an `XCTestCase` method with `XCTFail`.
// (`XCTFail` inside a `@Test` would be only a warning, and the test would pass. `Issue.record` inside an `XCTestCase`
// reaches XCTest only if XCTest installs Swift Testing's fallback event handler, which older Xcode versions don't.)
// Every helper takes the caller's source location, so failures point at the call site rather than at this file.
// `#_sourceLocation` can't be used as the default argument: it would require `import Testing` in every caller.

func assertTrue(_ actual: Bool, fileID: String = #fileID, filePath: StaticString = #filePath, line: Int = #line, column: Int = #column) {
    assertEquals(actual, true, fileID: fileID, filePath: filePath, line: line, column: column)
}

func assertFalse(_ actual: Bool, fileID: String = #fileID, filePath: StaticString = #filePath, line: Int = #line, column: Int = #column) {
    assertEquals(actual, false, fileID: fileID, filePath: filePath, line: line, column: column)
}

// Because assertEquals default messages are unreadable!
func assertNotEquals<T>(_ actual: T, _ expected: T, fileID: String = #fileID, filePath: StaticString = #filePath, line: Int = #line, column: Int = #column) where T: Equatable {
    if actual == expected {
        failExpectedActual("not \(expected)", actual, fileID: fileID, filePath: filePath, line: line, column: column)
    }
}

func assertNil(_ actual: Any?, fileID: String = #fileID, filePath: StaticString = #filePath, line: Int = #line, column: Int = #column) {
    if let actual {
        failExpectedActual("nil", actual, fileID: fileID, filePath: filePath, line: line, column: column)
    }
}

func assertNotNil(_ actual: Any?, fileID: String = #fileID, filePath: StaticString = #filePath, line: Int = #line, column: Int = #column) {
    if actual == nil {
        failExpectedActual("not nil", "nil", fileID: fileID, filePath: filePath, line: line, column: column)
    }
}

func assertEquals<T>(
    _ actual: T,
    _ expected: T,
    additionalMsg: String? = nil,
    fileID: String = #fileID,
    filePath: StaticString = #filePath,
    line: Int = #line,
    column: Int = #column,
) where T: Equatable {
    if actual != expected {
        failExpectedActual(expected, actual, additionalMsg: additionalMsg, fileID: fileID, filePath: filePath, line: line, column: column)
    }
}

func assertSucc<T>(_ actual: Result<T, some Any>, fileID: String = #fileID, filePath: StaticString = #filePath, line: Int = #line, column: Int = #column) {
    switch actual {
        case .failure: failExpectedActual("Result.success", actual, fileID: fileID, filePath: filePath, line: line, column: column)
        case .success: break
    }
}

func assertSucc<T>(
    _ actual: Result<T, some Any>,
    _ expected: T,
    fileID: String = #fileID,
    filePath: StaticString = #filePath,
    line: Int = #line,
    column: Int = #column,
) where T: Equatable {
    switch actual {
        case .failure: failExpectedActual("Result.success", actual, fileID: fileID, filePath: filePath, line: line, column: column)
        case .success(let actual): assertEquals(actual, expected, fileID: fileID, filePath: filePath, line: line, column: column)
    }
}

func assertFail<F>(
    _ actual: Result<some Any, F>,
    _ expected: F? = nil,
    fileID: String = #fileID,
    filePath: StaticString = #filePath,
    line: Int = #line,
    column: Int = #column,
) where F: Equatable {
    switch actual {
        case .success: failExpectedActual("Result.failure", actual, fileID: fileID, filePath: filePath, line: line, column: column)
        case .failure(let actual):
            if let expected {
                assertEquals(actual, expected, fileID: fileID, filePath: filePath, line: line, column: column)
            }
    }
}

func testParseSingleCommandSucc(
    _ command: String,
    _ expected: any CmdArgs,
    fileID: String = #fileID,
    filePath: StaticString = #filePath,
    line: Int = #line,
    column: Int = #column,
) {
    let parsed = parseCommand(command)
    let failure: (expected: Any, actual: Any)? = switch parsed {
        case .cmd(.cmd(let command)): command.args.equals(expected) ? nil : (expected, command.args)
        case .cmd(let shell): ("Parsed as single Command", "Parsed as shell: \(shell.shellOfCommandsDescription)")
        case .help: ("Parsed successfully", "Parsed as help")
        case .failure(let msg): ("Parsed successfully", "Failed to parse: \(msg.msg)")
    }
    if let failure {
        failExpectedActual(failure.expected, failure.actual, fileID: fileID, filePath: filePath, line: line, column: column)
    }
}

func testParseCommandHelp(_ command: String, fileID: String = #fileID, filePath: StaticString = #filePath, line: Int = #line, column: Int = #column) {
    switch parseCommand(command) {
        case .help: break
        case let parsed: failExpectedActual("Parsed as help", parsed, fileID: fileID, filePath: filePath, line: line, column: column)
    }
}

func failExpectedActual(
    _ expected: Any?,
    _ actual: Any?,
    additionalMsg: String? = nil,
    fileID: String = #fileID,
    filePath: StaticString = #filePath,
    line: Int = #line,
    column: Int = #column,
) {
    let additionalMsg = additionalMsg.map { "\n    Additional Message:\n        \($0)" } ?? ""
    fail(
        """
        Assertion failed\(additionalMsg)
            Expected:
                \(expected.prettyDescription)
            Actual:
                \(actual.prettyDescription)
        """,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column,
    )
}

/// Framework-agnostic replacement for `XCTFail`
func fail(_ msg: String, fileID: String = #fileID, filePath: StaticString = #filePath, line: Int = #line, column: Int = #column) {
    if Test.current == nil {
        XCTFail(msg, file: filePath, line: UInt(line))
    } else {
        // `Comment` and not a plain string: `String: LocalizedError` (StringEx.swift) would pick the `Issue.record(Error)` overload
        Issue.record(
            Comment(rawValue: msg),
            sourceLocation: SourceLocation(fileID: fileID, filePath: "\(filePath)", line: line, column: column),
        )
    }
}
