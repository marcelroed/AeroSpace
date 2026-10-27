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

        // The options come before `--`. The server parses them the same way
        let options = args.dropFirst().prefix { $0 != "--" }
        if let kind = CmdKind(rawValue: subcommand), kind != .execAndForget, options.contains(where: { $0 == "-h" || $0 == "--help" }) {
            exit(EXIT_CODE_ZERO, out: kind.help)
        }
        // Optimizations
        if args == [CmdKind._true.rawValue] { exit(EXIT_CODE_ZERO) }
        if args == [CmdKind._false.rawValue] { exit(1) }

        let stdin = options.contains("--stdin") ? readStdinOrExit() : ""
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

private func printVersionAndExit() async -> Never {
    let connection = NWConnection(to: NWEndpoint.unix(path: socketPath), using: .tcp)
    let serverVersionAndHash: String?
    if let e = await connection.initConnection().error {
        eprint(e.localizedDescription)
        serverVersionAndHash = nil
    } else {
        // Any answer carries the server version, even the failure of an empty request
        serverVersionAndHash = await send(connection, ClientRequest(args: [], stdin: "", windowId: nil, workspace: nil)).serverVersionAndHash
    }
    print(
        """
        aerospace CLI client version: \(cliClientVersionAndHash)
        AeroSpace.app server version: \(serverVersionAndHash ?? "Unknown. The server is not responding")
        """,
    )
    if serverVersionAndHash != nil && cliClientVersionAndHash != serverVersionAndHash {
        eprint(
            """
            Warning: AeroSpace client/server versions don't match. Possible fixes:
              - Restart AeroSpace.app (server restart is required after each update)
              - Reinstall and restart AeroSpace (corrupted installation)
            """,
        )
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
    if let e = await connection.writeAtomic(request).error {
        exit(EXIT_CODE_TWO, err: "Failed to write to server socket: \(e)")
    }
    switch await connection.readNonAtomic() {
        case .success(let answer):
            if let ans = try? JSONDecoder().decode(ServerAnswer.self, from: answer) { return ans }
            exit(EXIT_CODE_TWO, err: "Failed to parse server response: \(String(data: answer, encoding: .utf8).prettyDescription)")
        case .failure(let error):
            exit(EXIT_CODE_TWO, err: "Failed to read from server socket: \(error)")
    }
}

/// After a successful `subscribe` answer, the server sends an event per frame until the connection closes
private func printEventsAndExit(_ connection: NWConnection) async -> Never {
    while true {
        switch await connection.readNonAtomic() {
            case .success(let data):
                guard let str = String(data: data, encoding: .utf8) else { exit(EXIT_CODE_TWO, err: "Can't convert bytes to utf8 String") }
                print(str)
                unsafe fflush(stdout)
            case .failure(let e):
                exit(EXIT_CODE_TWO, err: "subscribe error: \(e)")
        }
    }
}
