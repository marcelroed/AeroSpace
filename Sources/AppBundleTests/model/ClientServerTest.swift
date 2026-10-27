@testable import AppBundle
import Common
import Foundation
import Testing

@Suite
struct ClientServerTest {
    @Test
    func testClientRequestJsonV1_decoding() throws {
        let data = #"{ "command": "deprecated", "args": ["foo", "bar"], "stdin": "stdin" }"#.data(using: .utf8)!
        let expected = ClientRequest(args: ["foo", "bar"], stdin: "stdin", windowId: nil, workspace: nil)
        #expect(try decode(data) == expected)
    }

    @Test
    func testClientRequestJsonV2_decoding() throws {
        let data = #"{ "args": ["foo", "bar"], "stdin": "stdin" }"#.data(using: .utf8)!
        let expected = ClientRequest(args: ["foo", "bar"], stdin: "stdin", windowId: nil, workspace: nil)
        #expect(try decode(data) == expected)
    }

    @Test
    func testClientRequestJsonV3_decoding() throws {
        let data = #"{ "args": ["foo", "bar"], "stdin": "stdin", "windowId": null, "workspace": null }"#.data(using: .utf8)!
        let expected = ClientRequest(args: ["foo", "bar"], stdin: "stdin", windowId: nil, workspace: nil)
        #expect(try decode(data) == expected)
    }

    @Test
    func testClientRequestJsonV3_decoding2() throws {
        let data = #"{ "args": ["foo", "bar"], "stdin": "stdin", "windowId": 1, "workspace": "foo" }"#.data(using: .utf8)!
        let expected = ClientRequest(args: ["foo", "bar"], stdin: "stdin", windowId: 1, workspace: "foo")
        #expect(try decode(data) == expected)
    }

    @Test
    func testClientRequestJsonV9999_decoding() {
        let data = #"{ "args": ["foo", "bar"], "stdin": "stdin", "yet another future field": 1 }"#.data(using: .utf8)!
        #expect(throws: Never.self) { try decode(data) }
    }

    @Test
    func testClientRequestJson_decodingMissingIsNull() throws {
        let data1 = #"{ "args": [], "stdin": "", "windowId": null }"#.data(using: .utf8)!
        #expect(try decode(data1) == ClientRequest(args: [], stdin: "", windowId: nil, workspace: nil))
        let data2 = #"{ "args": [], "stdin": "", "workspace": "w" }"#.data(using: .utf8)!
        #expect(try decode(data2) == ClientRequest(args: [], stdin: "", windowId: nil, workspace: "w"))
    }

    @Test
    func testClientRequestJson_decodingErrors() {
        let wrongFormat = "The data couldn’t be read because it isn’t in the correct format."
        let missing = "The data couldn’t be read because it is missing."
        let testData: [(json: String, kind: String, localizedDescription: String)] = [
            (#"{ "args": ["foo"], "stdin": "", "windowId": "x" }"#, #"typeMismatch ["windowId"]"#, wrongFormat),
            (#"{ "args": ["foo"], "stdin": "", "windowId": -1 }"#, "dataCorrupted []", wrongFormat),
            (#"{ "args": ["foo"], "stdin": "", "windowId": 1.5 }"#, "dataCorrupted []", wrongFormat),
            (#"{ "args": ["foo"], "stdin": "", "workspace": 1 }"#, #"typeMismatch ["workspace"]"#, wrongFormat),
            (#"{ "args": ["foo"], "stdin": "", "windowId": "x", "workspace": 1 }"#, #"typeMismatch ["windowId"]"#, wrongFormat),
            (#"{ "args": ["foo"], "windowId": "x" }"#, "keyNotFound stdin []", missing),
            (#"{ "stdin": "" }"#, "keyNotFound args []", missing),
            (#"{ "args": null, "stdin": "" }"#, #"valueNotFound ["args"]"#, missing),
            (#"{ "args": [1], "stdin": "" }"#, #"typeMismatch ["args", "Index 0"]"#, wrongFormat),
            (#"{ "args": [], "stdin": null }"#, #"valueNotFound ["stdin"]"#, missing),
            ("[]", "typeMismatch []", wrongFormat),
            ("not json", "dataCorrupted []", wrongFormat),
        ]
        for (json, expectedKind, expectedDescription) in testData {
            let data = json.data(using: .utf8)!
            let error = #expect(throws: (any Error).self) { try decode(data) }
            #expect(error?.localizedDescription == expectedDescription)
            let kind: String
            do {
                _ = try decode(data)
                kind = "success"
            } catch DecodingError.typeMismatch(_, let context) {
                kind = "typeMismatch \(context.codingPath.map(\.stringValue))"
            } catch DecodingError.valueNotFound(_, let context) {
                kind = "valueNotFound \(context.codingPath.map(\.stringValue))"
            } catch DecodingError.keyNotFound(let key, let context) {
                kind = "keyNotFound \(key.stringValue) \(context.codingPath.map(\.stringValue))"
            } catch DecodingError.dataCorrupted(let context) {
                kind = "dataCorrupted \(context.codingPath.map(\.stringValue))"
            } catch {
                kind = "\(error)"
            }
            #expect(kind == expectedKind, "\(json)")
        }
    }

    @Test
    func testClientRequestJsonCompatibility_encoding() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let testData = [
            (ClientRequest(args: ["args"], stdin: "stdin", windowId: 0, workspace: "foo"), #"{"args":["args"],"stdin":"stdin","windowId":0,"workspace":"foo"}"#),
            (ClientRequest(args: ["args"], stdin: "stdin", windowId: nil, workspace: nil), #"{"args":["args"],"stdin":"stdin"}"#),
        ]
        for (req, expectedJson) in testData {
            let data = try! encoder.encode(req)
            let str = String.init(data: data, encoding: .utf8)!
            #expect(str == expectedJson)
        }
    }

    @Test
    func testServerEventEncoding() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let testData: [(ServerEvent, String)] = [
            (.focusChanged(windowId: 123, workspace: "1"),
             #"{"_event":"focus-changed","windowId":123,"workspace":"1"}"#),

            (.focusedMonitorChanged(workspace: "2", monitorId_oneBased: 1),
             #"{"_event":"focused-monitor-changed","monitorId":1,"workspace":"2"}"#),

            (.workspaceChanged(workspace: "2", prevWorkspace: "1"),
             #"{"_event":"focused-workspace-changed","prevWorkspace":"1","workspace":"2"}"#),

            (.modeChanged(mode: "resize"),
             #"{"_event":"mode-changed","mode":"resize"}"#),

            (.windowDetected(windowId: 456, workspace: "1", appBundleId: "com.example", appName: "Example"),
             #"{"_event":"window-detected","appBundleId":"com.example","appName":"Example","windowId":456,"workspace":"1"}"#),

            (.bindingTriggered(mode: "main", binding: "alt-h"),
             #"{"_event":"binding-triggered","binding":"alt-h","mode":"main"}"#),
        ]
        for (event, expectedJson) in testData {
            let data = try! encoder.encode(event)
            let str = String(data: data, encoding: .utf8)!
            #expect(str == expectedJson)
        }
    }

    @Test
    func testServerEventDecoding() {
        let testData: [(String, ServerEvent)] = [
            (#"{"_event":"focus-changed","windowId":123,"workspace":"1"}"#,
             .focusChanged(windowId: 123, workspace: "1")),
            (#"{"_event":"focused-monitor-changed","workspace":"2","monitorId":1}"#,
             .focusedMonitorChanged(workspace: "2", monitorId_oneBased: 1)),
            (#"{"_event":"focused-workspace-changed","workspace":"2","prevWorkspace":"1"}"#,
             .workspaceChanged(workspace: "2", prevWorkspace: "1")),
            (#"{"_event":"mode-changed","mode":"resize"}"#,
             .modeChanged(mode: "resize")),
            (#"{"_event":"window-detected","windowId":456}"#,
             .windowDetected(windowId: 456, workspace: nil, appBundleId: nil, appName: nil)),
            (#"{"_event":"window-detected","windowId":456,"workspace":"1","appBundleId":"com.example","appName":"Example"}"#,
             .windowDetected(windowId: 456, workspace: "1", appBundleId: "com.example", appName: "Example")),
            (#"{"_event":"binding-triggered","mode":"main","binding":"alt-h"}"#,
             .bindingTriggered(mode: "main", binding: "alt-h")),
        ]
        for (json, expected) in testData {
            let data = json.data(using: .utf8)!
            let event = try! JSONDecoder().decode(ServerEvent.self, from: data)
            // ServerEvent isn't Equatable. Its description lists every stored property, so this compares all fields
            #expect(String(describing: event) == String(describing: expected))
        }
    }
}

private func decode(_ data: Data) throws -> ClientRequest {
    try JSONDecoder().decode(ClientRequest.self, from: data)
}
