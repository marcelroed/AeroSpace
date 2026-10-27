import AppKit
import Common
import Foundation
import ServiceManagement

let configDotfileName = ".aerospace.toml"

var defaultConfigUrl: URL {
    // The project's copy is for the debug builds that are not app bundles, and for the tests: the test runner's bundle has
    // no default config
    Bundle.main.url(forResource: "default-config", withExtension: "toml") ?? getDefaultConfigUrlFromProject()
}

private func getDefaultConfigUrlFromProject() -> URL {
    var url = URL(filePath: #filePath)
    check(FileManager.default.fileExists(atPath: url.path))
    // Not .git: a tarball or a copy of the sources has no .git, or the .git of an enclosing repo. Like projectRoot in the tests
    while !FileManager.default.fileExists(atPath: url.appending(component: "Package.swift").path) {
        check(url.path != "/", "Can't find the project root: no parent directory of \(#filePath) contains Package.swift")
        url.deleteLastPathComponent()
    }
    return url.appending(component: "docs/config-examples/default-config.toml")
}

func findCustomConfigUrl(configLocation: String? = serverArgs.configLocation) -> ConfigFile {
    // Use --config-path even if the file was deleted after the startup. Reading it then reports the missing file
    if let configLocation { return .file(URL(filePath: configLocation)) }
    let xdgConfigHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(filePath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/")
    let candidates: [URL] = [
        FileManager.default.homeDirectoryForCurrentUser.appending(path: configDotfileName),
        xdgConfigHome.appending(path: "aerospace").appending(path: "aerospace.toml"),
    ]
    let existingCandidates = candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
    return switch existingCandidates.count {
        case 0: .noCustomConfigExists
        case 1: .file(existingCandidates[0])
        default: .ambiguousConfigError(existingCandidates)
    }
}

enum ConfigFile {
    case file(URL), ambiguousConfigError(_ candidates: [URL]), noCustomConfigExists

    var urlOrNil: URL? {
        switch self {
            case .file(let url): url
            case .ambiguousConfigError, .noCustomConfigExists: nil
        }
    }
}

private struct ConfigFileWatcher: ~Copyable {
    private let source: DispatchSourceFileSystemObject
    private let fd: Int32

    init?(url: URL, onChange: @escaping @MainActor () -> Void) {
        fd = unsafe open(url.path, O_EVTONLY)
        if fd < 0 { return nil }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: .main,
        )
        source.setEventHandler { onChange() } // On the main queue, so the closure is main actor isolated
        source.setCancelHandler { [fd] in close(fd) }
        source.activate()
    }

    deinit {
        source.cancel()
    }
}

func syncConfigFileWatcher() { configAutoReload.sync() }

private let configAutoReload = ConfigAutoReload()

/// While auto-reload-config is on, reloads the config after its file changes
private final class ConfigAutoReload {
    // periphery:ignore - assign-only: the value keeps the watcher alive
    private var watcher: ConfigFileWatcher? = nil
    /// Editors write a file in several steps: reload after the last one
    private let debounced = LatestTaskSlot()
    private let debounceDelay: Duration = .milliseconds(200)

    func sync() {
        watcher = nil
        if !config.autoReloadConfig { return }
        watcher = ConfigFileWatcher(url: world.configUrl) { [debounced, debounceDelay] in
            debounced.replace {
                try await Task.sleep(for: debounceDelay)
                if let token: RunSessionGuard = .isServerEnabled {
                    try await world.sessions.light(.configAutoReload, token) {
                        _ = await reloadConfig_nonCancellable()
                    }
                }
            }
        }
    }
}

func syncStartAtLogin() {
    let service = SMAppService.mainApp
    switch true {
        case !config.startAtLogin: _ = try? service.unregister()
        case isDebug: print("'start-at-login = true' has no effect in debug builds")
        default: _ = try? service.register()
    }
}
