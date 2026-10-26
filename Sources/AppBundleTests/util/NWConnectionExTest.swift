@testable import AppBundle
import Common
import Foundation
import Network
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

    func testHandshakeWithoutServerFails() async {
        let path = FileManager.default.temporaryDirectory.appending(component: "aerospace-test-absent-\(UUID().uuidString.prefix(8)).sock").path
        let connection = NWConnection(to: .unix(path: path), using: .tcp)
        defer { connection.cancel() }

        switch await connection.initConnection().error {
            case .nwError: break
            case let other: failExpectedActual("nwError", other)
        }
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

    static func start(serverVersion: UInt32) async throws -> TestSocketServer {
        let path = FileManager.default.temporaryDirectory.appending(component: "aerospace-test-\(UUID().uuidString.prefix(8)).sock").path
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
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            listener.stateUpdateHandler = { state in
                switch state {
                    case .ready, .failed, .cancelled:
                        listener.stateUpdateHandler = nil
                        cont.resume()
                    default: break
                }
            }
            listener.start(queue: .global())
        }
        return TestSocketServer(path: path, listener: listener)
    }

    func stop() {
        listener.cancel()
        try? FileManager.default.removeItem(atPath: path)
    }
}
