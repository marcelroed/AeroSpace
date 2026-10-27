@testable import AppBundle
import Common
import Foundation
import Network
import os
import Testing

@Suite
struct NWConnectionExTest {
    @Test
    func roundTrip() async throws {
        let server = try await TestSocketServer.start()
        defer { server.stop() }
        let connection = NWConnection(to: .unix(path: server.path), using: .tcp)
        defer { connection.cancel() }

        #expect(await connection.initConnection().error == nil)
        let request = ClientRequest(args: ["list-workspaces", "--all"], stdin: "", windowId: 42, workspace: nil)
        #expect(await connection.writeAtomic(request).error == nil)
        let answer = try JSONDecoder().decode(ServerAnswer.self, from: await connection.readNonAtomic().get())
        #expect(answer == ServerAnswer(exitCode: 0, stdout: "list-workspaces --all", stderr: "windowId=Optional(42)", serverVersionAndHash: "test-server"))
    }

    @Test
    func readFailsWhenPeerClosesMidAnswer() async throws {
        let server = try await TestSocketServer.start(closeMidAnswer: true)
        defer { server.stop() }
        let connection = NWConnection(to: .unix(path: server.path), using: .tcp)
        defer { connection.cancel() }

        #expect(await connection.initConnection().error == nil)
        let request = ClientRequest(args: ["list-workspaces", "--all"], stdin: "", windowId: nil, workspace: nil)
        #expect(await connection.writeAtomic(request).error == nil)
        // The receive after the end of the stream fails. If it didn't, the read would spin forever (RB-08)
        switch await withTimeout(seconds: 5, { await connection.readNonAtomic() }) {
            case .failure: break
            case let other: Issue.record("Expected a failure, got \(other.map { "\($0)" } ?? "a timeout")")
        }
    }

    @Test
    func legacyClientGetsAnotherProtocolVersion() async throws {
        let server = try await TestSocketServer.start()
        defer { server.stop() }
        let connection = NWConnection(to: .unix(path: server.path), using: .tcp)
        defer { connection.cancel() }

        #expect(await connection.initConnection().error == nil)
        // A client from before the frames sends its protocol version, 1, and waits for the server's
        await connection.sendAndWait(withUnsafeBytes(of: UInt32(1)) { unsafe Data($0) })
        let serverVersion = await withTimeout(seconds: 5) { await connection.receiveUInt32() }
        #expect(serverVersion == .some(.some(2)))
    }

    @Test
    func initConnectionWithoutServerFails() async {
        let connection = NWConnection(to: .unix(path: testSocketPath()), using: .tcp)
        defer { connection.cancel() }

        #expect(await connection.initConnection().error != nil)
    }

    @Test
    func initConnectionFailsWhenCancelledBeforeReady() async throws {
        let server = try await TestSocketServer.start()
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
            case .some(.some): break
            case let other: Issue.record("Expected an error, got \(other.map { String(describing: $0) } ?? "a timeout")")
        }
    }
}

/// Never marks the connection ready, so it stays in .preparing
nonisolated private final class NeverReadyFramer: NWProtocolFramerImplementation {
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
nonisolated private func testSocketPath() -> String { "/tmp/aerospace-test-\(UUID().uuidString.prefix(8)).sock" }

/// Returns nil if `body` doesn't finish in time. `body` can't be cancelled and keeps running in that case
nonisolated private func withTimeout<T: Sendable>(seconds: Int, _ body: @escaping @Sendable () async -> T) async -> T? {
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

/// Mirrors the real server (server.swift): read one request, answer it
nonisolated private final class TestSocketServer: Sendable {
    let path: String
    private let listener: NWListener

    private init(path: String, listener: NWListener) {
        self.path = path
        self.listener = listener
    }

    /// - closeMidAnswer: announce an answer, then close the connection without sending it
    static func start(closeMidAnswer: Bool = false) async throws -> TestSocketServer {
        let path = testSocketPath()
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .unix(path: path)
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { connection in
            Task.startUnstructured {
                defer { connection.cancel() }
                connection.start(queue: .global())
                guard let raw = try? await connection.readRequestFrame()?.get() else { return }
                if closeMidAnswer {
                    await connection.sendAndWait(withUnsafeBytes(of: UInt32(100)) { unsafe Data($0) }) // The answer size
                    return
                }
                let request = ClientRequest.decodeJson(raw).getOrDie()
                let answer = ServerAnswer(
                    exitCode: 0,
                    stdout: request.args.joined(separator: " "),
                    stderr: "windowId=\(String(describing: request.windowId))",
                    serverVersionAndHash: "test-server",
                )
                _ = await connection.writeAtomic(answer)
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

extension NWConnection {
    /// Sends `data` as is, without the size of a frame
    nonisolated fileprivate func sendAndWait(_ data: Data) async {
        await withCheckedContinuation { cont in
            send(content: data, completion: .contentProcessed { _ in cont.resume() })
        }
    }

    /// Receives a bare UInt32, not a frame. nil if the connection ends first
    nonisolated fileprivate func receiveUInt32() async -> UInt32? {
        await withCheckedContinuation { cont in
            receive(minimumIncompleteLength: 4, maximumLength: 4) { data, _, _, _ in
                guard let data, data.count == 4 else { return cont.resume(returning: nil) }
                cont.resume(returning: unsafe data.withUnsafeBytes { pointer in unsafe pointer.loadUnaligned(as: UInt32.self) })
            }
        }
    }
}
