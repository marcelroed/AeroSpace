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
        let server = try await TestSocketServer.start(.answer)
        defer { server.stop() }
        let connection = NWConnection(to: .unix(path: server.path), using: .tcp)
        defer { connection.cancel() }

        await expectEqual(connection.initConnection().error, nil)
        let request = ClientRequest(args: ["list-workspaces", "--all"], stdin: "", windowId: 42, workspace: nil)
        await expectEqual(connection.writeAtomic(request).error, nil)
        let answer = try JSONDecoder().decode(ServerAnswer.self, from: await connection.readFrame().get())
        expectEqual(answer, ServerAnswer(exitCode: 0, stdout: "list-workspaces --all", stderr: "windowId=Optional(42)", serverVersionAndHash: "test-server"))
    }

    @Test(arguments: [(.closeMidAnswer, false), (.closeWithoutAnswer, true)] as [(TestSocketServer.Behavior, Bool)])
    func readFailsWhenPeerCloses(behavior: TestSocketServer.Behavior, closesBeforeTheFrame: Bool) async throws {
        let server = try await TestSocketServer.start(behavior)
        defer { server.stop() }
        let connection = NWConnection(to: .unix(path: server.path), using: .tcp)
        defer { connection.cancel() }

        await expectEqual(connection.initConnection().error, nil)
        let request = ClientRequest(args: ["list-workspaces", "--all"], stdin: "", windowId: nil, workspace: nil)
        await expectEqual(connection.writeAtomic(request).error, nil)
        // A read after the end of the stream must not spin (RB-08). The end of a subscription comes before a frame
        switch await withTimeout(seconds: 5, { await connection.readFrame() }) {
            case .failure(.endOfStream) where closesBeforeTheFrame, .failure(.closed) where !closesBeforeTheFrame: break
            case let other: Issue.record("Got \(other.map { "\($0)" } ?? "a timeout")")
        }
    }

    @Test
    func readOfServerThatDoesntAnswerTimesOut() async throws {
        let server = try await TestSocketServer.start(.neverAnswer)
        defer { server.stop() }
        let connection = NWConnection(to: .unix(path: server.path), using: .tcp)
        defer { connection.cancel() }

        await expectEqual(connection.initConnection().error, nil)
        let request = ClientRequest(args: [], stdin: "", windowId: nil, workspace: nil)
        await expectEqual(connection.writeAtomic(request).error, nil)
        // Like `aerospace --version` when the main thread of AeroSpace.app is stuck
        let answer = await withTimeout(seconds: 1) { await connection.readFrame() }
        #expect(answer == nil)
    }

    @Test
    func clientDetectsServerOfLegacyProtocol() async throws {
        let server = try await TestSocketServer.start(.legacyServer)
        defer { server.stop() }
        let connection = NWConnection(to: .unix(path: server.path), using: .tcp)
        defer { connection.cancel() }

        await expectEqual(connection.initConnection().error, nil)
        let request = ClientRequest(args: ["list-workspaces", "--all"], stdin: "", windowId: nil, workspace: nil)
        await expectEqual(connection.writeAtomic(request).error, nil)
        switch await withTimeout(seconds: 5, { await connection.readFrame() }) {
            case .failure(.legacyProtocol): break
            case let other: Issue.record("Expected .legacyProtocol, got \(other.map { "\($0)" } ?? "a timeout")")
        }
    }

    @Test
    func frameLongerThanMaxSizeIsNotRead() async throws {
        let server = try await TestSocketServer.start(.recordMaxSizeFailure)
        defer { server.stop() }
        let connection = NWConnection(to: .unix(path: server.path), using: .tcp)
        defer { connection.cancel() }

        await expectEqual(connection.initConnection().error, nil)
        let request = ClientRequest(args: [String(repeating: "x", count: 200)], stdin: "", windowId: nil, workspace: nil)
        await expectEqual(connection.writeAtomic(request).error, nil)
        let answer = try JSONDecoder().decode(ServerAnswer.self, from: await connection.readFrame().get())
        #expect(answer.stderr.starts(with: "The message is "), "\(answer)")
    }

    @Test
    func legacyClientGetsAnotherProtocolVersion() async throws {
        let server = try await TestSocketServer.start(.answer)
        defer { server.stop() }
        let connection = NWConnection(to: .unix(path: server.path), using: .tcp)
        defer { connection.cancel() }

        await expectEqual(connection.initConnection().error, nil)
        // A client from before the frames sends its protocol version, 1, and waits for the server's
        await connection.sendAndWait(withUnsafeBytes(of: UInt32(1)) { unsafe Data($0) })
        let serverVersion = await withTimeout(seconds: 5) { await connection.receiveUInt32() }
        expectEqual(serverVersion, .some(.some(2)))
    }

    @Test
    func initConnectionWithoutServerFails() async {
        let connection = NWConnection(to: .unix(path: testSocketPath()), using: .tcp)
        defer { connection.cancel() }

        #expect(await connection.initConnection().error != nil)
    }

    @Test
    func initConnectionFailsWhenCancelledBeforeReady() async throws {
        let server = try await TestSocketServer.start(.answer)
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

/// A server on a socket of its own: AeroSpace's, or one that mirrors it (read one request, answer it) or misbehaves
nonisolated final class TestSocketServer: Sendable {
    enum Behavior: Sendable {
        /// AeroSpace's server: ``serve(_:)``
        case aeroSpace
        case answer
        /// Announce an answer, then close the connection without sending it
        case closeMidAnswer
        case closeWithoutAnswer
        /// Read the request, and keep the connection open without answering
        case neverAnswer
        /// Like a server from before the frames: read the frame length as the client's protocol version, answer with
        /// version 1, and close the connection
        case legacyServer
        /// Accept requests of at most 100 bytes, and answer with the error
        case recordMaxSizeFailure
    }

    let path: String
    private let listener: NWListener

    private init(path: String, listener: NWListener) {
        self.path = path
        self.listener = listener
    }

    static func start(_ behavior: Behavior) async throws -> TestSocketServer {
        let path = testSocketPath()
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .unix(path: path)
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { connection in
            Task.startUnstructured {
                defer { connection.cancel() }
                connection.start(queue: .global())
                switch behavior {
                    case .aeroSpace: return await serve(connection)
                    case .answer, .closeMidAnswer, .closeWithoutAnswer, .neverAnswer: break
                    case .legacyServer:
                        _ = await connection.receiveUInt32()
                        await connection.sendAndWait(withUnsafeBytes(of: UInt32(1)) { unsafe Data($0) })
                        return
                    case .recordMaxSizeFailure:
                        if case .failure(let e) = await connection.readFrame(maxSize: 100) {
                            _ = await connection.writeAtomic(ServerAnswer(exitCode: 2, stderr: "\(e)", serverVersionAndHash: "test-server"))
                        }
                        return
                }
                let raw: Data
                switch await connection.readFrame() {
                    case .success(let it): raw = it
                    case .failure(.legacyProtocol): return await connection.answerLegacyHandshake()
                    case .failure: return
                }
                switch behavior {
                    case .closeMidAnswer:
                        await connection.sendAndWait(withUnsafeBytes(of: UInt32(100)) { unsafe Data($0) }) // The answer size
                        return
                    case .closeWithoutAnswer: return
                    case .neverAnswer: return await connection.readTillError() // Until the client closes the connection
                    case .answer, .aeroSpace, .legacyServer, .recordMaxSizeFailure: break
                }
                let request: ClientRequest
                do {
                    request = try JSONDecoder().decode(ClientRequest.self, from: raw)
                } catch {
                    Issue.record("The test server can't decode the request: \(error)")
                    return
                }
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
            throw ListenerNotReady(description: "Test socket listener at \(path) isn't ready: \(state.map { "\($0)" } ?? "timed out after \(timeoutSeconds)s")")
        }
        return server
    }

    func stop() {
        listener.cancel()
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Sends `request` on a new connection and reads the answer. The connection stays open for what follows the answer:
    /// the caller cancels it
    func send(_ request: ClientRequest) async throws -> (ServerAnswer, NWConnection) {
        let connection = NWConnection(to: .unix(path: path), using: .tcp)
        do {
            if let error = await connection.initConnection().error { throw error }
            if let error = await connection.writeAtomic(request).error { throw error }
            let answer = try JSONDecoder().decode(ServerAnswer.self, from: await connection.readFrame().get())
            return (answer, connection)
        } catch {
            connection.cancel()
            throw error
        }
    }
}

private struct ListenerNotReady: Error, CustomStringConvertible {
    let description: String
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
