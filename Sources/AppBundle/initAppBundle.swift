import AppKit
import Common
import Foundation
import Synchronization

/// Called from `AeroSpaceApp.init`, before SwiftUI builds the scenes. Returns the models that the scenes show
public func initAppBundle() -> Ui {
    // First: `--help`, `--version` and bad args exit here, and the menu bar model (`world.ui`) reads `--config-path`
    let args = parseServerArgs(Array(CommandLine.arguments.dropFirst()))
    parsedServerArgs.withLock { $0 = args }
    installTerminationHandler(AppServerTerminationHandler(platform: world.platform))
    Task.startUnstructured {
        await waitForAccessibilityPermission_nonCancellable()
        if isDebug {
            await toggleReleaseServerIfDebug(.off)
            interceptTermination(SIGINT)
        }
        // No screens (e.g. AeroSpace was started during display reconfiguration). The startup sessions below would
        // return early, and nothing would replay them: a regular session would register the existing windows later.
        // Wait for the screens here, before the hotkeys (config), the server and the observers can start a session
        while !world.platform.hasScreens { try? await Task.sleep(for: .milliseconds(100)) }

        bootstrapConfig()
        _ = reloadConfig()
        initWorkspaces() // After the config: it picks the workspaces

        startUnixSocketServer()
        GlobalObserver.initObserver()
        try await world.sessions.startup {
            smartLayoutAtStartup()
            _ = await config.afterStartupCommand.run(.defaultEnv, .emptyStdin)
        }
    }
    return world.ui
}

private func bootstrapConfig() {
    let result = reloadConfig(forceConfigUrl: defaultConfigUrl)
    let msg = """
        Can't load default config. Your installation is probably corrupted.
        Please don't modify \(defaultConfigUrl.description.singleQuoted)

        \(result.stdout)
        """
    check(result.isOk, msg)
}

/// The persistent workspaces, then the first snapshot of the monitors: it shows on each monitor a workspace that belongs to
/// it. The focus goes to the first workspace. `monitors`: tests only
func initWorkspaces(_ monitors: [MonitorInfo] = world.platform.monitors()) {
    Workspace.ensurePersistentWorkspaces()
    updateMonitors(monitors)
    _ = Workspace.all.first?.focusWorkspace()
}

private func smartLayoutAtStartup() {
    let root = focus.workspace.rootTilingContainerCreatingIfNeeded()
    root.layout = root.children.count <= 3 ? .tiles : .accordion
}

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

/// The server's command line args, parsed at the start of ``initAppBundle()``. The tests don't call it: they run with the
/// defaults. Any thread reads them (the AX writes check `isReadOnly`)
nonisolated var serverArgs: ServerArgs { parsedServerArgs.withLock { $0 } }
nonisolated private let parsedServerArgs: Mutex<ServerArgs> = Mutex(ServerArgs())

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
