@testable import AppBundle
import AppKit
import Common
import HotKey
import Testing

nonisolated let projectRoot: URL = {
    var url = URL(filePath: #filePath).absoluteURL
    check(FileManager.default.fileExists(atPath: url.path))
    while !FileManager.default.fileExists(atPath: url.appending(component: "Package.swift").path) {
        check(url.path != "/", "Package.swift isn't found in any parent directory of \(#filePath)")
        url.deleteLastPathComponent()
    }
    return url
}()

func setUpWorkspacesForTests() {
    world.reset(platform: FakePlatform())
    world.config.enableNormalizationFlattenContainers = false // Make layout tests more predictable
    world.config.enableNormalizationOppositeOrientationForNestedContainers = false // Make layout tests more predictable
    world.config.defaultRootContainerOrientation = .horizontal // Make default layout predictable

    // Don't create any bindings and workspaces for tests
    world.config.modes = [mainModeId: Mode(bindings: [:])]
    world.config.persistentWorkspaces = []

    updateMonitors([testMonitor])
    check(Workspace.get(byName: "setUpWorkspacesForTests").focusWorkspace())
    armFocusChangedCallbacks()
    Workspace.garbageCollectUnusedWorkspaces()
    check(focus.workspace.isEffectivelyEmpty)
    check(focus.workspace === Workspace.all.singleOrNil(), Workspace.all.map(\.description).joined(separator: ", "))
}

/// The only monitor of a test, unless it sets others with ``updateMonitors(_:)``
let testMonitor: MonitorInfo = makeTestMonitor(id: 1, "Test Monitor", Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080))
/// Right of ``testMonitor``
let rightTestMonitor: MonitorInfo = makeTestMonitor(id: 2, "Right Monitor", Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080))

private func makeTestMonitor(id: Int, _ name: String, _ rect: Rect) -> MonitorInfo {
    MonitorInfo(monitorAppKitNsScreenScreensId: id, name: name, rect: rect, visibleRect: rect, isMain: rect.topLeftCorner == .zero)
}

/// Parses `raw` like the config and `eval` do
func parseCommand(_ raw: String) -> Result<Shell<any Command>, CmdParseError> {
    Result { () throws(CmdParseError) in try parseShell(raw, allowExecAndForget: true, allowEval: true) }
}

extension Result<Shell<any Command>, CmdParseError> {
    /// The parse error. Nil if the command parses or asks for help
    var errorOrNil: String? {
        return switch self {
            case .failure(.invalid(let msg)): msg
            case .success, .failure(.help): nil
        }
    }

    var cmdOrNil: Shell<any Command>? { try? get() }
    var cmdOrDie: Shell<any Command> { cmdOrNil ?? dieT("\(self)") }
}

extension Result {
    var failureOrNil: Failure? {
        return switch self {
            case .failure(let failure): failure
            case .success: nil
        }
    }
}

/// The command of `raw` if it parses as a single command of type `T`, nil otherwise
func parsedCmd<T: Command>(_ raw: String, as _: T.Type) -> T? {
    guard case .success(.cmd(let command)) = parseCommand(raw) else { return nil }
    return command as? T
}

/// What a command printed, and its exit code
nonisolated struct CmdOutput: Equatable {
    var stdout: [String] = []
    var stderr: [String] = []
    var exitCode: Int32 = 0

    /// Exit code 0 without output
    static let ok = CmdOutput()

    /// Exit code 2 with `stderr`
    static func fail(_ stderr: String...) -> CmdOutput { CmdOutput(stderr: stderr, exitCode: 2) }
}

/// Runs `command` like the server runs a CLI request: `windowIdEnv` and `workspaceEnv` are the client's
/// AEROSPACE_WINDOW_ID and AEROSPACE_WORKSPACE. A parse error and help come back as output, the way the CLI prints them.
/// Every command behavior test runs its commands through this function, so that changes to how commands are parsed and
/// run touch only this function.
///
/// Check the output with `expectEqual`, which shows both outputs on a mismatch. `#expect` doesn't show the values of an
/// expression with `await`, so `#expect(await runCmd("...") == .ok)` would fail without the output
@discardableResult
func runCmd(_ command: String, stdin: String = "", windowIdEnv: WindowId? = nil, workspaceEnv: String? = nil) async -> CmdOutput {
    switch parseCommand(command) {
        case .success(let shell):
            let result = await shell.run(CmdEnv(windowId: windowIdEnv, workspaceName: workspaceEnv), CmdStdin(stdin))
            return CmdOutput(stdout: result.stdout, stderr: result.stderr, exitCode: result.exitCode)
        case .failure(.help(let kind)): return CmdOutput(stdout: [kind.help])
        case .failure(.invalid(let msg)): return CmdOutput(stderr: [msg], exitCode: EXIT_CODE_TWO)
    }
}

/// Parses `args` the way the server parses a CLI request, and runs the command like `runCmd`
func runCliArgs(_ args: [String], stdin: String = "") async -> CmdOutput {
    let command: any Command
    do throws(CmdParseError) {
        switch try parseRequest(args) {
            case .command(let it): command = it
            case .subscribe: return .ok
        }
    } catch {
        return switch error {
            case .help(let kind): CmdOutput(stdout: [kind.help])
            case .invalid(let msg): CmdOutput(stderr: [msg], exitCode: EXIT_CODE_TWO)
        }
    }
    let result = await Shell.cmd(command).run(CmdEnv(windowId: nil, workspaceName: nil), CmdStdin(stdin))
    return CmdOutput(stdout: result.stdout, stderr: result.stderr, exitCode: result.exitCode)
}

extension Workspace {
    /// Applies the workspace's placements, without the parks of the other workspaces
    func layoutWorkspace() {
        world.platform.apply(layoutPlacements())
    }
}

extension MonitorDescription {
    /// `.pattern` of a valid regex
    nonisolated static func pattern(_ raw: String) -> MonitorDescription { .pattern((try? CaseInsensitiveRegex(raw)).orDie()) }
}

extension HotkeyBinding {
    init(_ modifiers: NSEvent.ModifierFlags, _ keyCode: Key, _ commands: Shell<any Command>) {
        let descriptionWithKeyNotation = modifiers.isEmpty
            ? keyCode.toString()
            : modifiers.toString() + "-" + keyCode.toString()
        self.init(modifiers, keyCode, commands, descriptionWithKeyNotation: descriptionWithKeyNotation)
    }
}
