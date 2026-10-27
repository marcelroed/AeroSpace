import Common
import Darwin
import Foundation
import Network

let usage =
    """
    USAGE: \(CommandLine.arguments.first ?? "aerospace") [-h|--help] [-v|--version] <subcommand> [<args>...]

    SUBCOMMANDS:
    \(subcommandTable.joined(separator: "\n"))
    """

private let subcommandTable = CmdKind.allCases
    .filter { $0 != .execAndForget } // exec-and-forget isn't a CLI subcommand
    .map { ["  " + $0.rawValue, $0.purpose] }
    .sortedBy { $0[0] }
    .toPaddingTable(columnSeparator: "   ")

/// The CLI is thin: the server parses the args. The CLI answers only what needs no server: the usage, the version,
/// the help of a subcommand, and `true`/`false`
@main
struct Main {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let subcommand = args.first else { exit(EXIT_CODE_TWO, err: usage) }
        if subcommand == "--help" || subcommand == "-h" { exit(EXIT_CODE_ZERO, out: usage) }
        if subcommand == "--version" || subcommand == "-v" { await printVersionAndExit() }

        // The options come before `--`. The server parses them the same way: a word that starts with a dash is never the
        // value of an option there
        let options = args.dropFirst().prefix { $0 != "--" }
        let kind = CmdKind(rawValue: subcommand)
        if let kind, kind != .execAndForget, options.contains(where: { $0 == "-h" || $0 == "--help" }) {
            exit(EXIT_CODE_ZERO, out: kind.help)
        }
        // Optimizations
        if args == [CmdKind._true.rawValue] { exit(EXIT_CODE_ZERO) }
        if args == [CmdKind._false.rawValue] { exit(1) }

        // The server rejects --stdin for the other subcommands, so don't wait for stdin first
        let readsStdin = kind?.takesStdin == true && options.contains("--stdin")
        if readsStdin && isatty(STDIN_FILENO) != 0 {
            // Nothing would end the input. An empty one would fail later, with a message that doesn't say why
            exit(EXIT_CODE_TWO, err: "--stdin needs piped input, but stdin is a terminal")
        }
        let stdin = readsStdin ? readStdinOrExit() : ""
        let connection = await connectOrExit()
        let env = ProcessInfo.processInfo.environment
        let request = ClientRequest(
            args: args,
            stdin: stdin,
            windowId: env[AEROSPACE_WINDOW_ID].flatMap(UInt32.init),
            workspace: env[AEROSPACE_WORKSPACE],
        )
        let ans = await send(connection, request)

        if !ans.stdout.isEmpty { print(ans.stdout) }
        if !ans.stderr.isEmpty { eprint(ans.stderr) }
        if ans.exitCode != EXIT_CODE_ZERO && ans.serverVersionAndHash != cliClientVersionAndHash {
            eprint(
                """
                Warning: AeroSpace client/server versions don't match
                  - aerospace CLI client version: \(cliClientVersionAndHash)
                  - AeroSpace.app server version: \(ans.serverVersionAndHash)
                  Possible fixes:
                  - Restart AeroSpace.app (server restart is required after each update)
                  - Reinstall and restart AeroSpace (corrupted installation)
                """,
            )
        }
        if subcommand == CmdKind.subscribe.rawValue && ans.exitCode == EXIT_CODE_ZERO {
            await printEventsAndExit(connection)
        }
        exit(ans.exitCode)
    }
}

private func connectOrExit() async -> NWConnection {
    let connection = NWConnection(to: NWEndpoint.unix(path: socketPath), using: .tcp)
    if let e = await connection.initConnection().error {
        exit(EXIT_CODE_TWO, err: "Can't connect to AeroSpace server. Is AeroSpace.app running?\n\(e.localizedDescription)")
    }
    return connection
}

/// `--version` is how to tell what's wrong with AeroSpace.app, also when its main thread is stuck, so it doesn't wait long
private let versionAnswerTimeoutSeconds = 3

/// Prints the client version, and the server version if the server answers. Exits with 2 if the server is there but
/// doesn't answer: `--version` is how to tell that the CLI and the server don't fit
private func printVersionAndExit() async -> Never {
    let connection = NWConnection(to: NWEndpoint.unix(path: socketPath), using: .tcp)
    let server: Result<String, NoAnswer>?
    if let e = await connection.initConnection().error {
        eprint(e.localizedDescription)
        server = nil
    } else {
        // Any answer carries the server version, even the failure of an empty request
        let request = ClientRequest(args: [], stdin: "", windowId: nil, workspace: nil)
        let answer = await withTimeout(seconds: versionAnswerTimeoutSeconds) { await trySend(connection, request) }
        let timeout = NoAnswer.failed("AeroSpace.app accepted the connection, but didn't answer within \(versionAnswerTimeoutSeconds) seconds")
        server = (answer ?? .failure(timeout)).map(\.serverVersionAndHash)
    }
    let serverLine = switch server {
        case nil: "Unknown. The server is not responding"
        case .success(let it): it
        case .failure(.incompatibleProtocol): "Unknown (incompatible protocol)"
        case .failure(.failed): "Unknown (no answer)"
    }
    print(
        """
        aerospace CLI client version: \(cliClientVersionAndHash)
        AeroSpace.app server version: \(serverLine)
        """,
    )
    switch server {
        case .failure(let e): exit(EXIT_CODE_TWO, err: e.message)
        case .success(let it) where it != cliClientVersionAndHash:
            eprint(
                """
                Warning: AeroSpace client/server versions don't match. Possible fixes:
                  - Restart AeroSpace.app (server restart is required after each update)
                  - Reinstall and restart AeroSpace (corrupted installation)
                """,
            )
        case .success, nil: break
    }
    exit(EXIT_CODE_ZERO)
}

private func readStdinOrExit() -> String {
    var stdin = ""
    var index = 0
    while let line = readLine(strippingNewline: false) {
        stdin += line
        index += 1
        if index > 1000 {
            exit(EXIT_CODE_TWO, err: "stdin number of lines limit is exceeded")
        }
    }
    return stdin
}

private func send(_ connection: NWConnection, _ request: ClientRequest) async -> ServerAnswer {
    switch await trySend(connection, request) {
        case .success(let answer): answer
        case .failure(let e): exit(EXIT_CODE_TWO, err: e.message)
    }
}

private enum NoAnswer: Error {
    case incompatibleProtocol(serverVersion: String)
    case failed(String)

    var message: String {
        switch self {
            case .incompatibleProtocol(let serverVersion):
                """
                AeroSpace.app speaks protocol version \(serverVersion), and the CLI speaks version \(socketProtocolVersion).
                Restart AeroSpace.app (a restart is required after each update), or use the CLI of the same AeroSpace version
                """
            case .failed(let msg): msg
        }
    }
}

private func trySend(_ connection: NWConnection, _ request: ClientRequest) async -> Result<ServerAnswer, NoAnswer> {
    if let e = await connection.writeAtomic(request).error {
        return .failure(.failed("Failed to write to server socket: \(e)"))
    }
    switch await connection.readFrame() {
        case .success(let raw):
            if let answer = try? JSONDecoder().decode(ServerAnswer.self, from: raw), answer.protocolVersion == socketProtocolVersion {
                return .success(answer)
            }
            if let version = decodeProtocolVersion(raw), version != socketProtocolVersion {
                return .failure(.incompatibleProtocol(serverVersion: "\(version)"))
            }
            return .failure(.failed("Failed to parse server response: \(String(data: raw, encoding: .utf8).prettyDescription)"))
        case .failure(.legacyProtocol): return .failure(.incompatibleProtocol(serverVersion: "1"))
        case .failure(.closed): return .failure(.failed("AeroSpace.app closed the connection without answering. Did it crash?"))
        case .failure(let e): return .failure(.failed("Failed to read from server socket: \(e)"))
    }
}

/// After a successful `subscribe` answer, the server sends an event per frame until the connection closes
private func printEventsAndExit(_ connection: NWConnection) async -> Never {
    while true {
        switch await connection.readFrame() {
            case .success(let data):
                guard let str = String(data: data, encoding: .utf8) else { exit(EXIT_CODE_TWO, err: "Can't convert bytes to utf8 String") }
                print(str)
                unsafe fflush(stdout)
            case .failure(let e):
                exit(EXIT_CODE_TWO, err: "subscribe error: \(e)")
        }
    }
}
