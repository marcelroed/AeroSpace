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

    let request = ClientRequest(args: ["enable", state.rawValue], stdin: "", windowId: nil, workspace: nil)
    let error: String? = if let e = await connection.writeAtomic(request).error {
        "\(e)"
    } else {
        switch await connection.readFrame() {
            case .success(let raw): decodeProtocolVersion(raw) == socketProtocolVersion ? nil : "It speaks another protocol version"
            case .failure(let e): "\(e)"
        }
    }
    if let error {
        // Otherwise both window managers stay enabled. The old handshake isn't worth speaking for this single request
        eprint("Warning: the release AeroSpace.app isn't turned \(state.rawValue). Quit it, or turn it \(state.rawValue) by hand. \(error)")
    }
}

nonisolated private let serverVersionAndHash: String = "\(aeroSpaceAppVersion) \(gitHash)"

/// Answers the one request of the connection. Runs off the main actor: the connection I/O doesn't wait for the main
/// thread
nonisolated private func newConnection(_ connection: NWConnection) async {
    func answer(exitCode: Int32, stdout: String = "", stderr: String = "") async {
        let answer = ServerAnswer(exitCode: exitCode, stdout: stdout, stderr: stderr, serverVersionAndHash: serverVersionAndHash)
        _ = await connection.writeAtomic(answer)
    }

    let rawRequest: Data
    switch await connection.readFrame(maxSize: maxRequestSize) {
        case .success(let it): rawRequest = it
        case .failure(.legacyProtocol): return await connection.answerLegacyHandshake()
        case .failure(.endOfStream), .failure(.closed): return // Nobody to answer
        case .failure(let err): return await answer(exitCode: EXIT_CODE_TWO, stderr: "Can't read the request. \(err)")
    }
    // One JSON decode on the common path. The version probe decodes again, so it runs only for other requests
    let request: ClientRequest
    do {
        request = try JSONDecoder().decode(ClientRequest.self, from: rawRequest)
    } catch {
        if let message = protocolMismatchMessage(rawRequest) {
            return await answer(exitCode: EXIT_CODE_TWO, stderr: message)
        }
        let msg = """
            Can't parse request \(String(describing: String(data: rawRequest, encoding: .utf8)).singleQuoted).
            Error: \(error.localizedDescription)
            """
        return await answer(exitCode: EXIT_CODE_TWO, stderr: msg)
    }
    if request.protocolVersion != socketProtocolVersion, let message = protocolMismatchMessage(rawRequest) {
        return await answer(exitCode: EXIT_CODE_TWO, stderr: message)
    }
    switch await handle(request) {
        case .answer(let exitCode, let stdout, let stderr):
            await answer(exitCode: exitCode, stdout: stdout, stderr: stderr)
        case .subscribe(let args):
            await answer(exitCode: EXIT_CODE_ZERO)
            await handleSubscribeAndWaitTillError(connection, args)
    }
}

/// The answer to a request that isn't of this protocol version, nil for one that is. A request without a version, or
/// that isn't a JSON object at all, isn't of this version either: the client doesn't speak this protocol
nonisolated func protocolMismatchMessage(_ rawRequest: Data) -> String? {
    let clientVersion = decodeProtocolVersion(rawRequest)
    if clientVersion == socketProtocolVersion { return nil }
    let client = clientVersion.map { "The CLI speaks protocol version \($0)" } ?? "The CLI speaks a protocol without a version"
    return """
        \(client), and AeroSpace.app speaks version \(socketProtocolVersion).
        Use the CLI of the same AeroSpace version, or restart AeroSpace.app (a restart is required after each update)
        """
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
        return try await world.sessions.light(.socketServer(request.args), token) { () throws in
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
