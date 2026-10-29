import AppKit
import Darwin
import Foundation
import Synchronization

public let socketPath: String = "/tmp/\(aeroSpaceAppId)-\(unixUserName).sock"
public let unixUserName = NSUserName()
public let mainModeId = "main"

/// The thread that terminates the process: the first one to die, quit or get SIGINT/SIGTERM. Only it restores the windows
/// (RB-06, RB-07)
private let terminatingThreadId: Mutex<UInt64?> = Mutex(nil)

public enum TerminationClaim: Equatable {
    /// No thread was terminating: the caller is now
    case first
    /// The caller was already terminating: a die inside the termination handler, or the handler called from a die
    case sameThread
    /// Another thread is terminating: it restores the windows, then ends the process. The caller parks
    case otherThread
}

/// The termination handler and every die claim termination for their thread
public func claimTermination() -> TerminationClaim {
    let me = currentThreadId()
    return terminatingThreadId.withLock { owner in
        if let owner { return owner == me ? .sameThread : .otherThread }
        owner = me
        return .first
    }
}

/// For a thread that lost ``claimTermination()``: the terminating thread ends the process. That thread waits for an AX
/// thread at most 2 s and never for main, so a parked thread can't hold it up
public func parkForever() -> Never {
    let never = DispatchSemaphore(value: 0)
    while true { never.wait() }
}

/// Kernel id of the calling thread. Cheap, and unlike `Thread.current` usable in async code
public func currentThreadId() -> UInt64 {
    var id: UInt64 = 0
    unsafe pthread_threadid_np(nil, &id)
    return id
}

public func bugPrompt(
    _ __message: String = "",
    isDie: Bool = false,
    file: StaticString = #fileID,
    line: Int = #line,
    column: Int = #column,
    function: String = #function,
) -> String {
    let _message = __message.contains("\n") ? "\n" + __message.prefixLines(with: "    ") : __message
    let thread = Thread.current
    // AppKit doesn't document NSScreen as thread-safe, and the dying thread is often an AX thread
    let notMainThread = "n/a (not main thread)"
    let monitorCount = thread.isMainThread ? NSScreen.screens.count.description : notMainThread
    let screensHaveSeparateSpaces = thread.isMainThread ? NSScreen.screensHaveSeparateSpaces.description : notMainThread
    return """
        Please report to:
            https://github.com/nikitabobko/AeroSpace/discussions/categories/potential-bugs
            Please describe what you did to trigger this error

        Message: \(_message)
        Version: \(aeroSpaceAppVersion)
        Git hash: \(gitHash)
        Date: \(Date.now)
        Thread name: \(thread.name.prettyDescription)
        Is main thread: \(thread.isMainThread)
        macOS version: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Coordinate: \(file):\(line):\(column) \(function)
        server: \(terminationHandler != nil)
        die: \(isDie)
        Monitor count: \(monitorCount)
        Displays have separate spaces: \(screensHaveSeparateSpaces)

        Stacktrace:
        \(getStringStacktrace())
        """
}

public func dieT<T>(
    _ __message: String = "",
    file: StaticString = #fileID,
    line: Int = #line,
    column: Int = #column,
    function: String = #function,
) -> T {
    let message = bugPrompt(__message, isDie: true, file: file, line: line, column: column, function: function)
    let claim = claimTermination()
    if let terminationHandler { // The server, not the CLI or tests
        showMessageInGui(
            filenameIfConsoleApp: claim == .first ? "aerospace-runtime-error.txt" : "aerospace-runtime-error-recursion.txt",
            title: "AeroSpace Runtime Error",
            message: message,
        )
        switch claim {
            // On the dying thread, without the main thread: main may be busy or blocked (RB-71)
            case .first: terminationHandler.beforeTermination()
            case .sameThread: break // A die inside the termination handler: don't restore again
            case .otherThread: parkForever() // Let the terminating thread finish its restore and end the process
        }
    }
    fatalError("\n" + message)
}

public func getStringStacktrace() -> String { Thread.callStackSymbols.joined(separator: "\n") }

@inlinable public func die(
    _ message: String = "",
    file: StaticString = #fileID,
    line: Int = #line,
    column: Int = #column,
    function: String = #function,
) -> Never {
    dieT(message, file: file, line: line, column: column, function: function)
}

public func check(
    _ condition: Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #fileID,
    line: Int = #line,
    column: Int = #column,
    function: String = #function,
) {
    if !condition {
        die(message(), file: file, line: line, column: column, function: function)
    }
}

extension CaseIterable where Self: RawRepresentable, RawValue == String {
    public static var cliArgsCases: [String] { allCases.map(\.rawValue) }
    public static var unionLiteral: String { cliArgsCases.joinedCliArgs }
}

extension [String] {
    public var joinedCliArgs: String { "(" + self.joined(separator: "|") + ")" }
}

public func + <K, V>(lhs: [K: V], rhs: [K: V]) -> [K: V] {
    lhs.merging(rhs) { _, r in r }
}

extension String {
    public func removePrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}

extension URL {
    public func open(with url: URL) {
        NSWorkspace.shared.open([self], withApplicationAt: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

public func eprint(_ msg: String) {
    unsafe fputs(msg + "\n", stderr)
}

public func exit(_ exitCode: Int32, out: String? = nil, err: String? = nil) -> Never {
    if let out { print(out) }
    if let err { eprint(err) }
    Darwin.exit(exitCode)
}
