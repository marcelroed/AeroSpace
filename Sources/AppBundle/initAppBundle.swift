import AppKit
import Common
import Foundation

/// Called from `AeroSpaceApp.init`, before SwiftUI builds the scenes
public func initAppBundle() {
    installTerminationHandler(AppServerTerminationHandler())
    _ = serverArgs // `--help`, `--version` and bad args exit here. The menu bar model reads `--config-path`
    Task.startUnstructured {
        await waitForAccessibilityPermission_nonCancellable()
        if isDebug {
            await toggleReleaseServerIfDebug(.off)
            interceptTermination(SIGINT)
        }
        // No screens (e.g. AeroSpace was started during display reconfiguration). The startup sessions below would
        // return early, and nothing would replay them: a regular session would register the existing windows later.
        // Wait for the screens here, before the hotkeys (config), the server and the observers can start a session
        while !hasScreens { try? await Task.sleep(for: .milliseconds(100)) }

        await bootstrapConfig_nonCancellable()
        _ = await reloadConfig_nonCancellable()

        startUnixSocketServer()
        GlobalObserver.initObserver()
        Workspace.garbageCollectUnusedWorkspaces() // init workspaces
        _ = Workspace.all.first?.focusWorkspace()
        await runHeavyCompleteRefreshSession(
            .startup,
            // It's important for the first initialization to be non cancellable
            // to make sure that isStartup propagates to all places
            assumeCancellable: false,
            layoutWorkspaces: false,
        )
        try await runLightSession(.startup, .forceRun) {
            smartLayoutAtStartup()
            _ = await config.afterStartupCommand.run(.defaultEnv, .emptyStdin)
        }
    }
}

private func bootstrapConfig_nonCancellable() async {
    let result = await reloadConfig_nonCancellable(forceConfigUrl: defaultConfigUrl)
    let msg = """
        Can't load default config. Your installation is probably corrupted.
        Please don't modify \(defaultConfigUrl.description.singleQuoted)

        \(result.stdout)
        """
    check(result.isOk, msg)
}

private func smartLayoutAtStartup() {
    let root = focus.workspace.rootTilingContainer
    root.layout = root.children.count <= 3 ? .tiles : .accordion
}

var isStartup: Bool { refreshSessionEvent?.isStartup == true }

struct ServerArgs: Sendable {
    var configLocation: String? = nil
    var isReadOnly: Bool = false
}

nonisolated private let serverHelp = """
    USAGE: \(CommandLine.arguments.first ?? "AeroSpace.app/Contents/MacOS/AeroSpace") [<options>]

    OPTIONS:
      -h, --help              Print help
      -v, --version           Print AeroSpace.app version
      --config-path <path>    Config path. It will take priority over ~/.aerospace.toml
                              and ${XDG_CONFIG_HOME}/aerospace/aerospace.toml
      --read-only             Disable window management.
                              Useful if you want to use only debug-windows or other query commands.
    """

/// The server's command line args. Parsed at the start of `initAppBundle`. Tests don't pass any
nonisolated let serverArgs: ServerArgs = isUnitTest ? ServerArgs() : parseServerArgs(Array(CommandLine.arguments.dropFirst()))

nonisolated private func parseServerArgs(_ args: [String]) -> ServerArgs {
    var result = ServerArgs()
    if args.contains(where: { $0 == "-h" || $0 == "--help" }) {
        exit(EXIT_CODE_ZERO, out: serverHelp)
    }
    var index = 0
    while index < args.count {
        let current = args[index]
        index += 1
        switch current {
            case "--version", "-v":
                exit(EXIT_CODE_ZERO, out: "\(aeroSpaceAppVersion) \(gitHash)")
            case "--config-path":
                switch args.getOrNil(atIndex: index) {
                    case let arg?: result.configLocation = arg
                    case nil: exit(EXIT_CODE_TWO, err: "Missing <path> in --config-path flag")
                }
                index += 1
            case "--read-only": // todo rename to '--disabled' and unite with disabled feature
                result.isReadOnly = true
            case "-NSDocumentRevisionsDebugMode" where isDebug:
                // Skip Xcode CLI args.
                // Usually it's '-NSDocumentRevisionsDebugMode NO'/'-NSDocumentRevisionsDebugMode YES'
                while args.getOrNil(atIndex: index)?.starts(with: "-") == false { index += 1 }
            default:
                exit(EXIT_CODE_TWO, err: "Unrecognized flag \(current.singleQuoted)")
        }
    }
    if let path = result.configLocation, !FileManager.default.fileExists(atPath: path) {
        exit(EXIT_CODE_TWO, err: "\(path) doesn't exist")
    }
    return result
}
