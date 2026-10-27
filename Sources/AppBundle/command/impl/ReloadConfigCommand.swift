import AppKit
import Common

struct ReloadConfigCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var noGui = false
    var dryRun = false

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var result = Self()
        while let option = try a.nextOption() {
            switch option {
                case "--no-gui": result.noGui = true
                case "--dry-run": result.dryRun = true
                case "--warnings-as-errors": break // No effect: config warnings no longer exist. Scripts still pass it
                default: throw .unknownOption(option)
            }
        }
        try a.end()
        return result
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let result = await reloadConfig_nonCancellable(args: self)
        if !result.stdout.isEmpty {
            cx.out(result.stdout)
        }
        if !result.isOk { throw .silent }
    }
}

struct ReloadConfigResult {
    let isOk: Bool
    let stdout: String
}

/// Stays `async` only so that the call sites don't change. Nothing in it suspends
func reloadConfig_nonCancellable(
    args: ReloadConfigCommand = ReloadConfigCommand(),
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
