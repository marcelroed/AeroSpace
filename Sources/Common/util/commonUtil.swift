import AppKit
import Darwin
import Foundation
import Synchronization

public let socketPath = "/tmp/\(aeroSpaceAppId)-\(unixUserName).sock"
public let unixUserName = NSUserName()
public let mainModeId = "main"

@TaskLocal
public var refreshSessionEvent: RefreshSessionEvent? = nil

@TaskLocal
private var recursionDetectorDuringTermination = false

/// Threads that entered `dieT`. Such a thread never runs its run loop again: an AX app thread waits in `MainActor.runSync`
/// until `beforeTermination` returns, so `beforeTermination` must not wait for a job on it
private let dyingThreads = Mutex(Set<ObjectIdentifier>())

public func isDyingThread(_ thread: Thread) -> Bool {
    let id = ObjectIdentifier(thread)
    return dyingThreads.withLock { $0.contains(id) }
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
        refreshSessionEvent: \(refreshSessionEvent.prettyDescription)
        Date: \(Date.now)
        Thread name: \(thread.name.prettyDescription)
        Is main thread: \(thread.isMainThread)
        axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken.prettyDescription)
        macOS version: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Coordinate: \(file):\(line):\(column) \(function)
        recursionDetectorDuringTermination: \(recursionDetectorDuringTermination)
        cli: \(isCli)
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
    let id = ObjectIdentifier(Thread.current)
    dyingThreads.withLock { _ = $0.insert(id) }
    let message = bugPrompt(__message, isDie: true, file: file, line: line, column: column, function: function)
    if !isUnitTest && isServer {
        showMessageInGui(
            filenameIfConsoleApp: recursionDetectorDuringTermination
                ? "aerospace-runtime-error-recursion.txt"
                : "aerospace-runtime-error.txt",
            title: "AeroSpace Runtime Error",
            message: message,
        )
    }
    if let terminationHandler, !recursionDetectorDuringTermination {
        MainActor.runSync {
            $recursionDetectorDuringTermination.withValue(true) {
                terminationHandler.beforeTermination()
            }
        }
    }
    fatalError("\n" + message)
}

extension MainActor {
    static func runSync(block: @escaping @MainActor () -> ()) {
        switch Thread.isMainThread {
            case true: MainActor.assumeIsolated(block)
            case false: DispatchQueue.main.asyncAndWait { block() }
        }
    }
}

public enum RefreshSessionEvent: Sendable, CustomStringConvertible {
    case configAutoReload
    case globalObserver(String)
    case globalObserverLeftMouseUp
    case menuBarButton
    case hotkeyBinding
    case startup
    case socketServer(any CmdArgs)
    case resetManipulatedWithMouse
    case ax(String)
    case focusFollowsMouse

    public var isStartup: Bool {
        if case .startup = self { return true } else { return false }
    }

    public var isFocusFollowsMouse: Bool {
        if case .focusFollowsMouse = self { return true } else { return false }
    }

    public var description: String {
        switch self {
            case .ax(let str): "ax(\(str))"
            case .configAutoReload: "configAutoReload"
            case .globalObserver(let str): "globalObserver(\(str))"
            case .globalObserverLeftMouseUp: "globalObserverLeftMouseUp"
            case .hotkeyBinding: "hotkeyBinding"
            case .menuBarButton: "menuBarButton"
            case .resetManipulatedWithMouse: "resetManipulatedWithMouse"
            case .socketServer(let args): "socketServer: \(args)"
            case .startup: "startup"
            case .focusFollowsMouse: "focusFollowsMouse"
        }
    }
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

// The test target defines this class (AppBundleTests/SwiftTestingSupport.swift). Whether XCTest is loaded depends on
// the test runner. Computed once: code under test runs only after the test bundle, and so the class, is loaded
public let isUnitTest: Bool = NSClassFromString("AeroSpaceUnitTestMarker") != nil

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

extension Bool {
    /// Implication
    /// | a     | b     | a.implies(b) |
    /// |-------|-------|--------------|
    /// | false | false | true         |
    /// | false | true  | true         |
    /// | true  | false | false        |
    /// | true  | true  | true         |
    public func implies(_ mustHold: @autoclosure () -> Bool) -> Bool { !self || mustHold() }
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
