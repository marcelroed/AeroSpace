@testable import AppBundle
import Common
import Foundation
import Network
import os
import XCTest

final class NWConnectionExTest: XCTestCase {
    func testHandshakeAndRoundTrip() async throws {
        let server = try await TestSocketServer.start(serverVersion: SOCKET_PROTOCOL_VERSION)
        defer { server.stop() }
        let connection = NWConnection(to: .unix(path: server.path), using: .tcp)
        defer { connection.cancel() }

        assertNil(await connection.initConnection().error)
        let request = ClientRequest(args: ["list-workspaces", "--all"], stdin: "", windowId: 42, workspace: nil)
        assertNil(await connection.writeAtomic(request).error)
        let answer = try JSONDecoder().decode(ServerAnswer.self, from: await connection.readNonAtomic().get())
        assertEquals(answer.exitCode, 0)
        assertEquals(answer.stdout, "list-workspaces --all")
        assertEquals(answer.stderr, "windowId=Optional(Optional(42))")
        assertEquals(answer.serverVersionAndHash, "test-server")
    }

    func testHandshakeVersionMismatch() async throws {
        let server = try await TestSocketServer.start(serverVersion: SOCKET_PROTOCOL_VERSION + 41)
        defer { server.stop() }
        let connection = NWConnection(to: .unix(path: server.path), using: .tcp)
        defer { connection.cancel() }

        switch await connection.initConnection().error {
            case .customError(let msg):
                assertEquals(
                    msg,
                    """
                    Client SOCKET_PROTOCOL_VERSION: \(SOCKET_PROTOCOL_VERSION)
                    Server SOCKET_PROTOCOL_VERSION: \(SOCKET_PROTOCOL_VERSION + 41)

                    The client and server versions are incompatible. (Potential fix: restart AeroSpace)
                    """,
                )
            case let other: failExpectedActual("customError", other)
        }
    }

    func testReadFailsWhenPeerClosesMidAnswer() async throws {
        let server = try await TestSocketServer.start(serverVersion: SOCKET_PROTOCOL_VERSION, closeMidAnswer: true)
        defer { server.stop() }
        let connection = NWConnection(to: .unix(path: server.path), using: .tcp)
        defer { connection.cancel() }

        assertNil(await connection.initConnection().error)
        let request = ClientRequest(args: ["list-workspaces", "--all"], stdin: "", windowId: nil, workspace: nil)
        assertNil(await connection.writeAtomic(request).error)
        // The receive after the end of the stream fails. If it didn't, the read would spin forever (RB-08)
        switch await withTimeout(seconds: 5, { await connection.readNonAtomic() }) {
            case .failure: break
            case let other: failExpectedActual("failure", other.map { "\($0)" } ?? "timed out")
        }
    }

    func testHandshakeWithoutServerFails() async {
        let connection = NWConnection(to: .unix(path: testSocketPath()), using: .tcp)
        defer { connection.cancel() }

        switch await connection.initConnection().error {
            case .nwError: break
            case let other: failExpectedActual("nwError", other)
        }
    }

    func testHandshakeFailsWhenCancelledBeforeReady() async throws {
        let server = try await TestSocketServer.start(serverVersion: SOCKET_PROTOCOL_VERSION)
        defer { server.stop() }
        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(NWProtocolFramer.Options(definition: NeverReadyFramer.definition), at: 0)
        let connection = NWConnection(to: .unix(path: server.path), using: params)
        defer { connection.cancel() }

        // Cancel the connection while it is stuck in .preparing. If initConnection ignored .cancelled, it would never
        // return (RB-46)
        Task.startUnstructured {
            for _ in 0 ..< 500 {
                guard case .setup = connection.state else { break }
                try? await Task.sleep(for: .milliseconds(10))
            }
            connection.cancel()
        }
        switch await withTimeout(seconds: 5, { await connection.initConnection().error }) {
            case .some(.some(.nwError)): break
            case let other: failExpectedActual("nwError", other.map { String(describing: $0) } ?? "timed out")
        }
    }
}

/// Never marks the connection ready, so it stays in .preparing
private final class NeverReadyFramer: NWProtocolFramerImplementation {
    static let definition = NWProtocolFramer.Definition(implementation: NeverReadyFramer.self)
    static var label: String { "NeverReady" }
    init(framer: NWProtocolFramer.Instance) {}
    func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult { .willMarkReady }
    func handleInput(framer: NWProtocolFramer.Instance) -> Int { 0 }
    func handleOutput(framer: NWProtocolFramer.Instance, message: NWProtocolFramer.Message, messageLength: Int, isComplete: Bool) {}
    func wakeup(framer: NWProtocolFramer.Instance) {}
    func stop(framer: NWProtocolFramer.Instance) -> Bool { true }
    func cleanup(framer: NWProtocolFramer.Instance) {}
}

/// $TMPDIR can be too long for a unix socket path (sun_path is capped at 104 bytes). Like the real socketPath, use /tmp
private func testSocketPath() -> String { "/tmp/aerospace-test-\(UUID().uuidString.prefix(8)).sock" }

/// Returns nil if `body` doesn't finish in time. `body` can't be cancelled and keeps running in that case
private func withTimeout<T: Sendable>(seconds: Int, _ body: @escaping @Sendable () async -> T) async -> T? {
    await withCheckedContinuation { cont in
        let isDone = OSAllocatedUnfairLock(initialState: false)
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

/// Mirrors the handshake of the real server (server.swift): read client version, answer with own version, then
/// answer each request
private final class TestSocketServer: Sendable {
    let path: String
    private let listener: NWListener

    private init(path: String, listener: NWListener) {
        self.path = path
        self.listener = listener
    }

    /// - closeMidAnswer: announce an answer, then close the connection without sending it
    static func start(serverVersion: UInt32, closeMidAnswer: Bool = false) async throws -> TestSocketServer {
        let path = testSocketPath()
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .unix(path: path)
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { connection in
            Task.startUnstructured {
                defer { connection.cancel() }
                connection.start(queue: .global())
                guard await connection.readUInt32().getIgnoringErrorsOrNil() != nil else { return }
                if await connection.writeUInt32(serverVersion).error != nil { return }
                while let raw = await connection.readNonAtomic().getIgnoringErrorsOrNil() {
                    if closeMidAnswer {
                        _ = await connection.writeUInt32(100) // The answer size
                        return
                    }
                    let request = ClientRequest.decodeJson(raw).getOrDie()
                    let answer = ServerAnswer(
                        exitCode: 0,
                        stdout: request.args.joined(separator: " "),
                        stderr: "windowId=\(String(describing: request.windowId))",
                        serverVersionAndHash: "test-server",
                    )
                    if await connection.writeAtomic(answer).error != nil { return }
                }
            }
        }
        let timeoutSeconds = 5
        let state: NWListener.State? = await withCheckedContinuation { cont in
            let isDone = OSAllocatedUnfairLock(initialState: false)
            let resume: @Sendable (NWListener.State?) -> Void = { state in
                // Make sure to resume continuation only once
                let wasAlreadyDone = isDone.withLock { isDone in
                    defer { isDone = true }
                    return isDone
                }
                if !wasAlreadyDone { cont.resume(returning: state) }
            }
            listener.stateUpdateHandler = { state in
                switch state {
                    case .ready, .failed, .cancelled:
                        listener.stateUpdateHandler = nil
                        resume(state)
                    default: break
                }
            }
            listener.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeoutSeconds)) { resume(nil) }
        }
        let server = TestSocketServer(path: path, listener: listener)
        guard case .ready = state else {
            server.stop()
            throw "Test socket listener at \(path) isn't ready: \(state.map { "\($0)" } ?? "timed out after \(timeoutSeconds)s")"
        }
        return server
    }

    func stop() {
        listener.cancel()
        try? FileManager.default.removeItem(atPath: path)
    }
}
