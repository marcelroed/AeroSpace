@testable import AppBundle
import Common
import Foundation
import Testing

/// The socket protocol between the CLI and AeroSpace.app (clientServer.swift)
@Suite
struct ClientServerTest {
    /// Unknown fields are ignored, and a missing optional field is nil
    @Test(arguments: [
        (#"{ "protocolVersion": 2, "args": ["foo", "bar"], "stdin": "stdin", "windowId": 1, "workspace": "foo" }"#, ClientRequest(args: ["foo", "bar"], stdin: "stdin", windowId: 1, workspace: "foo")),
        (#"{ "protocolVersion": 2, "args": ["foo", "bar"], "stdin": "stdin", "yet another future field": 1 }"#, ClientRequest(args: ["foo", "bar"], stdin: "stdin", windowId: nil, workspace: nil)),
        (#"{ "protocolVersion": 2, "args": [], "stdin": "", "windowId": null }"#, ClientRequest(args: [], stdin: "", windowId: nil, workspace: nil)),
        (#"{ "protocolVersion": 2, "args": [], "stdin": "", "workspace": "w" }"#, ClientRequest(args: [], stdin: "", windowId: nil, workspace: "w")),
    ] as [(String, ClientRequest)])
    func decoding(json: String, expected: ClientRequest) throws {
        try expectEqual(decode(json), expected)
    }

    @Test(arguments: [
        #"{ "protocolVersion": 2, "args": ["foo"], "stdin": "", "windowId": "x" }"#,
        #"{ "protocolVersion": 2, "args": ["foo"], "stdin": "", "windowId": -1 }"#,
        #"{ "protocolVersion": 2, "args": ["foo"], "stdin": "", "windowId": 1.5 }"#,
        #"{ "protocolVersion": 2, "args": ["foo"], "stdin": "", "workspace": 1 }"#,
        #"{ "protocolVersion": 2, "args": ["foo"] }"#,
        #"{ "protocolVersion": 2, "stdin": "" }"#,
        #"{ "protocolVersion": 2, "args": null, "stdin": "" }"#,
        #"{ "protocolVersion": 2, "args": [1], "stdin": "" }"#,
        #"{ "protocolVersion": 2, "args": [], "stdin": null }"#,
        #"{ "args": [], "stdin": "" }"#,
        "[]",
        "not json",
    ] as [String])
    func decodingFails(json: String) {
        #expect(throws: (any Error).self) { try decode(json) }
    }

    @Test(arguments: [
        (ClientRequest(args: ["args"], stdin: "stdin", windowId: 0, workspace: "foo"), #"{"args":["args"],"protocolVersion":2,"stdin":"stdin","windowId":0,"workspace":"foo"}"#),
        (ClientRequest(args: ["args"], stdin: "stdin", windowId: nil, workspace: nil), #"{"args":["args"],"protocolVersion":2,"stdin":"stdin"}"#),
    ] as [(ClientRequest, String)])
    func encoding(request: ClientRequest, json: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        expectEqual(String(decoding: try encoder.encode(request), as: UTF8.self), json)
    }

    @Test(arguments: [
        (#"{ "protocolVersion": 3, "args": [] }"#, 3),
        (#"{ "protocolVersion": 2 }"#, 2),
        (#"{ "args": [], "stdin": "" }"#, nil),
        (#"{ "protocolVersion": "2" }"#, nil),
        ("[]", nil),
        ("not json", nil),
    ] as [(String, Int?)])
    func protocolVersionOfAnyMessage(json: String, version: Int?) {
        expectEqual(decodeProtocolVersion(Data(json.utf8)), version)
    }

    @Test(arguments: [
        (#"{ "protocolVersion": 2, "args": [] }"#, nil),
        (#"{ "protocolVersion": 3, "args": [] }"#, "The CLI speaks protocol version 3"),
        (#"{ "args": [], "stdin": "" }"#, "The CLI speaks a protocol without a version"),
        ("not json", "The CLI speaks a protocol without a version"),
    ] as [(String, String?)])
    func requestOfAnotherProtocolGetsTheProtocolMessage(json: String, client: String?) {
        let expected: String? = client.map { "\($0), and AeroSpace.app speaks version 2.\n\(protocolMismatchFix)" }
        expectEqual(protocolMismatchMessage(Data(json.utf8)), expected)
    }

    /// The server's answers that run no command. It answers help and parse errors even while it's disabled
    @Test(.aeroSpaceGlobalState, arguments: [
        (["close", "--help"], 2, true, CmdOutput(stdout: [CmdKind.close.help])),
        (["bogus"], 2, true, .fail("Unrecognized subcommand 'bogus'")),
        (["close"], 3, true, .fail("The CLI speaks protocol version 3, and AeroSpace.app speaks version 2.\n\(protocolMismatchFix)")),
        (["close"], 2, false, .fail("\(aeroSpaceAppName) server is disabled and doesn't accept commands. You can use 'aerospace enable on' to enable the server")),
        (["close", "-h"], 2, false, CmdOutput(stdout: [CmdKind.close.help])),
    ] as [([String], Int, Bool, CmdOutput)])
    func serverAnswers(args: [String], protocolVersion: Int, isEnabled: Bool, expected: CmdOutput) async throws {
        world.isEnabled = isEnabled
        let server = try await TestSocketServer.start(.aeroSpace)
        defer { server.stop() }
        let request = ClientRequest(args: args, stdin: "", windowId: nil, workspace: nil, protocolVersion: protocolVersion)
        let (answer, connection) = try await server.send(request)
        connection.cancel()
        expectEqual(CmdOutput(answer), expected)
        expectEqual(answer.serverVersionAndHash, "\(aeroSpaceAppVersion) \(gitHash)")
    }

    /// The JSON that `subscribe` clients parse. A local table: ServerEvent's factories are main-actor isolated
    @Test
    func serverEventRoundTrip() throws {
        let rows: [(ServerEvent, String)] = [
            (.focusChanged(windowId: 123, workspace: "1"), #"{"_event":"focus-changed","windowId":123,"workspace":"1"}"#),
            (.focusedMonitorChanged(workspace: "2", monitorId_oneBased: 1), #"{"_event":"focused-monitor-changed","monitorId":1,"workspace":"2"}"#),
            (.workspaceChanged(workspace: "2", prevWorkspace: "1"), #"{"_event":"focused-workspace-changed","prevWorkspace":"1","workspace":"2"}"#),
            (.modeChanged(mode: "resize"), #"{"_event":"mode-changed","mode":"resize"}"#),
            (.windowDetected(windowId: 456, workspace: nil, appBundleId: nil, appName: nil), #"{"_event":"window-detected","windowId":456}"#),
            (
                .windowDetected(windowId: 456, workspace: "1", appBundleId: "com.example", appName: "Example"),
                #"{"_event":"window-detected","appBundleId":"com.example","appName":"Example","windowId":456,"workspace":"1"}"#,
            ),
            (.bindingTriggered(mode: "main", binding: "alt-h"), #"{"_event":"binding-triggered","binding":"alt-h","mode":"main"}"#),
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for (event, json) in rows {
            expectEqual(String(decoding: try encoder.encode(event), as: UTF8.self), json)
            // ServerEvent isn't Equatable. Its description lists every stored property, so this compares all fields
            let decoded = try JSONDecoder().decode(ServerEvent.self, from: Data(json.utf8))
            expectEqual(String(describing: decoded), String(describing: event), "\(json)")
        }
    }
}

extension CmdOutput {
    /// What the CLI prints for `answer`
    fileprivate init(_ answer: ServerAnswer) {
        self.init(stdout: answer.stdout.isEmpty ? [] : [answer.stdout], stderr: answer.stderr.isEmpty ? [] : [answer.stderr], exitCode: answer.exitCode)
    }
}

nonisolated private let protocolMismatchFix =
    "Use the CLI of the same AeroSpace version, or restart AeroSpace.app (a restart is required after each update)"

private func decode(_ json: String) throws -> ClientRequest {
    try JSONDecoder().decode(ClientRequest.self, from: Data(json.utf8))
}
