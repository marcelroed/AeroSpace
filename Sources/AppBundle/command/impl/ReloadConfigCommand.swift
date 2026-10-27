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
        if !result.stderr.isEmpty {
            io.err(result.stderr)
        }
        return .from(bool: result.isOk)
    }
}

struct ReloadConfigResult {
    let isOk: Bool
    let stdout: String
    let stderr: String
}

/// Stays `async` only so that the call sites don't change. Nothing in it suspends
func reloadConfig_nonCancellable(
    args: ReloadConfigCmdArgs = ReloadConfigCmdArgs(rawArgs: []),
    forceConfigUrl: URL? = nil,
) async -> ReloadConfigResult {
    let (url, parsed) = loadConfig(forceUrl: forceConfigUrl)
    var errors = parsed.errors.map { $0.description(.error) }
    var warnings = parsed.warnings.map { $0.description(.warning) }
    if !args.noGui {
        MessageModel.shared.message = reloadMessage(url, errors: errors, warnings: warnings, args.warningsAsErrors)
    }
    if parsed.allowReloadConfig && !args.dryRun {
        applyConfig(parsed.config, url: url, containsWarnings: !warnings.isEmpty)
    }
    if !args.dryRun {
        // Re-arm even if the reload failed. The watcher follows the file, not the path, and an atomic save replaces the file
        syncConfigFileWatcher()
    }
    if args.warningsAsErrors {
        errors += warnings
        warnings = []
    }
    return ReloadConfigResult(isOk: errors.isEmpty, stdout: errors.joined(separator: "\n\n"), stderr: warnings.joined(separator: "\n\n"))
}

/// Synchronous on purpose: no hotkey press, CLI request or window rule can observe a half-applied config
private func applyConfig(_ newConfig: Config, url: URL, containsWarnings: Bool) {
    TrayMenuModel.shared.lastReloadConfigContainedWarnings = containsWarnings
    resetHotKeys()
    config = newConfig
    configUrl = url
    registerHotkeys(for: activeMode) // A removed mode keeps its stale name and gets no hotkeys
    syncStartAtLogin()
    syncFocusFollowsMouse(config)
}

private func reloadMessage(_ url: URL, errors: [String], warnings: [String], _ warningsAsErrors: Bool) -> Message? {
    let path = url.absoluteURL.path.singleQuoted
    let header: String? = if !errors.isEmpty {
        "Failed to parse \(path). \(errors.count) error(s). \(warnings.count) warning(s)"
    } else if warningsAsErrors && !warnings.isEmpty {
        "Parsed \(path) with \(warnings.count) warning(s). Feel free to close this window."
    } else {
        nil
    }
    return header.map { Message(body: "\($0)\n\n\((errors + warnings).joined(separator: "\n\n"))", containsWarnings: !warnings.isEmpty) }
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
