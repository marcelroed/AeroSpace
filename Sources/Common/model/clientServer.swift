import Foundation

// The CLI talks to AeroSpace.app over a unix socket (socketPath). Every message is a frame: its length as a
// little-endian UInt32, then that many bytes of JSON (NWConnectionEx.swift).
//
// One request per connection. The client sends a ClientRequest, the server answers with one ServerAnswer. After a
// successful `subscribe` answer, the server sends a frame per ServerEvent until the connection closes.

public let EXIT_CODE_ZERO: Int32 = 0
public let EXIT_CODE_TWO: Int32 = 2

public struct ClientRequest: Codable, Sendable, Equatable {
    /// The subcommand and its args. The server parses them
    public let args: [String]
    /// Empty unless the command reads stdin (`--stdin`)
    public let stdin: String
    /// The client's AEROSPACE_WINDOW_ID env variable
    public let windowId: UInt32?
    /// The client's AEROSPACE_WORKSPACE env variable
    public let workspace: String?

    public init(args: [String], stdin: String, windowId: UInt32?, workspace: String?) {
        self.args = args
        self.stdin = stdin
        self.windowId = windowId
        self.workspace = workspace
    }
}

public struct ServerAnswer: Codable, Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let serverVersionAndHash: String

    public init(exitCode: Int32, stdout: String = "", stderr: String = "", serverVersionAndHash: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.serverVersionAndHash = serverVersionAndHash
    }
}
