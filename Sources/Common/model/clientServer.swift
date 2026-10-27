import Foundation

public let SOCKET_PROTOCOL_VERSION: UInt32 = 1

public struct ServerAnswer: Codable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public var stderr: String
    public let serverVersionAndHash: String

    public init(
        exitCode: Int32,
        stdout: String = "",
        stderr: String = "",
        serverVersionAndHash: String,
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.serverVersionAndHash = serverVersionAndHash
    }
}

public struct ClientRequest: Codable, Sendable, ConvenienceMutable, Equatable {
    public let args: [String]
    public let stdin: String

    // Double Optional to encode explicit null into JSON
    public var windowId: UInt32??  // Please forward AEROSPACE_WINDOW_ID env variable here
    public var workspace: String?? // Please forward AEROSPACE_WORKSPACE env variable here

    public init(
        args: [String],
        stdin: String,
        windowId: UInt32?,
        workspace: String?,
    ) {
        self.args = args
        self.stdin = stdin
        self.windowId = .some(windowId)
        self.workspace = .some(workspace)
    }

    public static func decodeJson(_ data: Data) -> Result<ClientRequest, String> {
        Result { try JSONDecoder().decode(Self.self, from: data) }.mapError { $0.localizedDescription }
    }

    enum CodingKeys: String, CodingKey {
        case args
        case stdin
        case windowId
        case workspace
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        args = try container.decode([String].self, forKey: .args)
        stdin = try container.decode(String.self, forKey: .stdin)
        // Missing key: nil. Explicit null: .some(nil)
        windowId = try container.contains(.windowId) ? .some(container.decodeIfPresent(UInt32.self, forKey: .windowId)) : nil
        workspace = try container.contains(.workspace) ? .some(container.decodeIfPresent(String.self, forKey: .workspace)) : nil
    }
}
