import AppKit
import Common
import Network

func startUnixSocketServer() {
    try? FileManager.default.removeItem(atPath: socketPath)
    let params = NWParameters.tcp
    params.requiredLocalEndpoint = .unix(path: socketPath)
    let listener = Result { try NWListener(using: params) }.getOrDie()
    listener.newConnectionHandler = { connection in
        Task.startUnstructured {
            defer { connection.cancel() }
            connection.start(queue: .global())
            await newConnection(connection)
        }
    }
    listener.start(queue: .global())
}

/// nonisolated: the termination handler blocks the main thread until it finishes
nonisolated func toggleReleaseServerIfDebug(_ state: ToggleEnum) async {
    if serverArgs.isReadOnly || !isDebug { return }
    let socketFile = "/tmp/\(stableAeroSpaceAppId)-\(unixUserName).sock"
    let connection = NWConnection(to: NWEndpoint.unix(path: socketFile), using: .tcp)
    defer { connection.cancel() }
    if await connection.initConnection().error != nil { // Can't connect, AeroSpace.app is not running
        return
    }

    _ = await connection.writeAtomic(ClientRequest(args: ["enable", state.rawValue], stdin: "", windowId: nil, workspace: nil))
    _ = await connection.readNonAtomic()
}

nonisolated private let serverVersionAndHash = "\(aeroSpaceAppVersion) \(gitHash)"

/// Answers the one request of the connection. Runs off the main actor: the connection I/O doesn't wait for the main
/// thread
nonisolated private func newConnection(_ connection: NWConnection) async {
    func answer(exitCode: Int32, stdout: String = "", stderr: String = "") async {
        let answer = ServerAnswer(exitCode: exitCode, stdout: stdout, stderr: stderr, serverVersionAndHash: serverVersionAndHash)
        _ = await connection.writeAtomic(answer)
    }

    let rawRequest: Data
    switch await connection.readRequestFrame() {
        case .success(let it): rawRequest = it
        case .failure(let err): return await answer(exitCode: EXIT_CODE_TWO, stderr: "Error: \(err)")
        case nil: return
    }
    let request: ClientRequest
    do {
        request = try JSONDecoder().decode(ClientRequest.self, from: rawRequest)
    } catch {
        let msg = """
            Can't parse request \(String(describing: String(data: rawRequest, encoding: .utf8)).singleQuoted).
            Error: \(error.localizedDescription)
            """
        return await answer(exitCode: EXIT_CODE_TWO, stderr: msg)
    }
    switch await handle(request) {
        case .answer(let exitCode, let stdout, let stderr):
            await answer(exitCode: exitCode, stdout: stdout, stderr: stderr)
        case .subscribe(let args):
            await answer(exitCode: EXIT_CODE_ZERO)
            await handleSubscribeAndWaitTillError(connection, args)
    }
}

private enum RequestOutcome {
    case answer(exitCode: Int32, stdout: String = "", stderr: String = "")
    case subscribe(SubscribeArgs)
}

/// Parses the request, then runs the command. Help and parse errors are answered even if the server is disabled
private func handle(_ request: ClientRequest) async -> RequestOutcome {
    let command: any Command
    do throws(CmdParseError) {
        switch try parseRequest(request.args) {
            case .command(let it): command = it
            case .subscribe(let args): return .subscribe(args)
        }
    } catch {
        return switch error {
            case .help(let kind): .answer(exitCode: EXIT_CODE_ZERO, stdout: kind.help)
            case .invalid(let msg): .answer(exitCode: EXIT_CODE_TWO, stderr: msg)
        }
    }
    guard let token: RunSessionGuard = .isServerEnabled(orIsEnableCommand: command) else {
        return .answer(
            exitCode: EXIT_CODE_TWO,
            stderr: "\(aeroSpaceAppName) server is disabled and doesn't accept commands. " +
                "You can use 'aerospace enable on' to enable the server",
        )
    }
    do {
        return try await runLightSession(.socketServer(request.args), token) { () throws in
            let env = CmdEnv(windowId: request.windowId, workspaceName: request.workspace)
            let result = await command.run(env, CmdStdin(request.stdin))
            return .answer(
                exitCode: result.exitCode,
                stdout: result.stdout.joined(separator: "\n"),
                stderr: result.stderr.joined(separator: "\n"),
            )
        }
    } catch {
        return .answer(exitCode: EXIT_CODE_TWO, stderr: "Fail to await main thread. \(error.localizedDescription)")
    }
}
