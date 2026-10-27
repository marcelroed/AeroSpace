import AppKit
import Common

struct ReloadConfigCommand: Command {
    let args: ReloadConfigCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        let result = await reloadConfig_nonCancellable(args: args)
        if !result.stdout.isEmpty {
            io.out(result.stdout)
        }
        return .from(bool: result.isOk)
    }
}

struct ReloadConfigResult {
    let isOk: Bool
    let stdout: String
}

/// Stays `async` only so that the call sites don't change. Nothing in it suspends
func reloadConfig_nonCancellable(
    args: ReloadConfigCmdArgs = ReloadConfigCmdArgs(rawArgs: []),
    forceConfigUrl: URL? = nil,
) async -> ReloadConfigResult {
    let (url, parsed) = loadConfig(forceUrl: forceConfigUrl)
    let errors = parsed.errors.map(\.description)
    if !args.noGui {
        MessageModel.shared.message = errors.isEmpty
            ? nil
            : Message(body: "Failed to parse \(url.absoluteURL.path.singleQuoted). \(errors.count) error(s)\n\n\(errors.joined(separator: "\n\n"))")
    }
    if parsed.allowReloadConfig && !args.dryRun {
        applyConfig(parsed.config, url: url)
    }
    if !args.dryRun {
        // Re-arm even if the reload failed. The watcher follows the file, not the path, and an atomic save replaces the file
        syncConfigFileWatcher()
    }
    return ReloadConfigResult(isOk: errors.isEmpty, stdout: errors.joined(separator: "\n\n"))
}

/// Synchronous on purpose: no hotkey press, CLI request or window rule can observe a half-applied config
private func applyConfig(_ newConfig: Config, url: URL) {
    resetHotKeys()
    config = newConfig
    configUrl = url
    registerHotkeys(for: activeMode) // A removed mode keeps its stale name and gets no hotkeys
    syncStartAtLogin()
    syncFocusFollowsMouse(config)
}

/// Finds and parses the config. A fatal result (ambiguous or unreadable file, TOML syntax error) must not be applied
func loadConfig(forceUrl: URL?) -> (url: URL, result: ParseConfigResult) {
    let url: URL
    if let forceUrl {
        url = forceUrl
    } else {
        switch findCustomConfigUrl() {
            case .file(let found): url = found
            case .noCustomConfigExists: url = defaultConfigUrl
            case .ambiguousConfigError(let candidates):
                return (defaultConfigUrl, .fatal("Ambiguous config error. Several configs found:\n" + candidates.map(\.path).joined(separator: "\n")))
        }
    }
    do {
        return (url, parseConfig(try String(contentsOf: url, encoding: .utf8)))
    } catch {
        return (url, .fatal("Can't read contents of \(url.path.singleQuoted) as a utf8 string: \(error.localizedDescription)"))
    }
}
