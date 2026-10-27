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

@MainActor func reloadConfig_nonCancellable(
    args: ReloadConfigCmdArgs = ReloadConfigCmdArgs(rawArgs: []),
    forceConfigUrl: URL? = nil,
) async -> ReloadConfigResult {
    let result = readConfig(forceConfigUrl: forceConfigUrl)
    let parseResult = result.parseConfigResult
    let warningsAsErrors = args.warningsAsErrors

    var errors = parseResult.errors.map { $0.description(.error) }
    var warnings = parseResult.warnings.map { $0.description(.warning) }
    let containsWarnings = !parseResult.warnings.isEmpty

    if !args.noGui {
        let path = result.configUrl.absoluteURL.path.singleQuoted
        let header: String? = if !errors.isEmpty {
            "Failed to parse \(path). \(errors.count) error(s). \(warnings.count) warning(s)"
        } else if warningsAsErrors && !warnings.isEmpty {
            "Parsed \(path) with \(warnings.count) warning(s). Feel free to close this window."
        } else {
            nil
        }
        MessageModel.shared.message = header.map {
            Message(body: "\($0)\n\n\((errors + warnings).joined(separator: "\n\n"))", containsWarnings: containsWarnings)
        }
    }
    if parseResult.allowReloadConfig && !args.dryRun {
        TrayMenuModel.shared.lastReloadConfigContainedWarnings = containsWarnings
        resetHotKeys()
        config = parseResult.config
        configUrl = result.configUrl
        await activateMode_nonCancellable(activeMode)
        syncStartAtLogin()
        syncFocusFollowsMouse(config)
    }
    if !args.dryRun {
        // Re-arm even if the reload failed. The watcher follows the file, not the path, and an atomic save replaces the file
        syncConfigFileWatcher()
    }

    if warningsAsErrors {
        errors += warnings
        warnings = []
    }

    return ReloadConfigResult(
        isOk: errors.isEmpty,
        stdout: errors.joined(separator: "\n\n"),
        stderr: warnings.joined(separator: "\n\n"),
    )
}
