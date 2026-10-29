import Foundation

// The CLI talks to AeroSpace.app over a unix socket (socketPath). Every message is a frame: its length as a
// little-endian UInt32, then that many bytes of JSON (NWConnectionEx.swift).
//
// One request per connection. The client sends a ClientRequest, the server answers with one ServerAnswer. After a
// successful `subscribe` answer, the server sends a frame per ServerEvent until the connection closes.
//
// Both carry `protocolVersion`, so that the next change to the request or the answer is detected, not misread: the
// server answers a request of another version, or without one, with an error, and the client reports an answer of
// another version. Version 1 was the protocol before the frames, which started with a version handshake
// (FrameReadError.legacyProtocol). JSONEncoder writes the fields in no particular order.

public let socketProtocolVersion = 2

/// The longest request frame the server reads. The CLI checks it before sending: the server closes the connection
/// after the frame length, while the CLI is still writing, so the CLI wouldn't get the server's error
public let maxRequestSize: UInt32 = 16 << 20

public let EXIT_CODE_ZERO: Int32 = 0
/// A "no" rather than a failure
public let EXIT_CODE_ONE: Int32 = 1
public let EXIT_CODE_TWO: Int32 = 2

public struct ClientRequest: Codable, Sendable, Equatable {
    public let protocolVersion: Int
    /// The subcommand and its args. The server parses them
    public let args: [String]
    /// Empty unless the command reads stdin (`--stdin`)
    public let stdin: String
    /// The client's AEROSPACE_WINDOW_ID env variable
    public let windowId: UInt32?
    /// The client's AEROSPACE_WORKSPACE env variable
    public let workspace: String?

    public init(args: [String], stdin: String, windowId: UInt32?, workspace: String?, protocolVersion: Int = socketProtocolVersion) {
        self.protocolVersion = protocolVersion
        self.args = args
        self.stdin = stdin
        self.windowId = windowId
        self.workspace = workspace
    }
}

public struct ServerAnswer: Codable, Sendable, Equatable {
    public let protocolVersion: Int
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let serverVersionAndHash: String

    public init(exitCode: Int32, stdout: String = "", stderr: String = "", serverVersionAndHash: String) {
        protocolVersion = socketProtocolVersion
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.serverVersionAndHash = serverVersionAndHash
    }
}

/// The protocol version of a request or an answer of any version. nil if the message isn't a JSON object, or has no version
public func decodeProtocolVersion(_ data: Data) -> Int? {
    struct Probe: Decodable { let protocolVersion: Int? }
    return (try? JSONDecoder().decode(Probe.self, from: data))?.protocolVersion
}
