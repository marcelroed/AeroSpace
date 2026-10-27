@testable import AppBundle
import AppKit
import Common
import HotKey

let projectRoot: URL = {
    var url = URL(filePath: #filePath).absoluteURL
    check(FileManager.default.fileExists(atPath: url.path))
    while !FileManager.default.fileExists(atPath: url.appending(component: "Package.swift").path) {
        check(url.path != "/", "Package.swift isn't found in any parent directory of \(#filePath)")
        url.deleteLastPathComponent()
    }
    return url
}()

@MainActor
func setUpWorkspacesForTests() {
    config = defaultConfig
    configUrl = defaultConfigUrl
    config.enableNormalizationFlattenContainers = false // Make layout tests more predictable
    config.enableNormalizationOppositeOrientationForNestedContainers = false // Make layout tests more predictable
    config.defaultRootContainerOrientation = .horizontal // Make default layout predictable

    // Don't create any bindings and workspaces for tests
    config.modes = [mainModeId: Mode(bindings: [:])]
    config.persistentWorkspaces = []

    for workspace in Workspace.all {
        for child in workspace.children {
            child.unbindFromParent()
        }
    }
    for container: TreeNode in [macosMinimizedWindowsContainer, macosPopupWindowsContainer] { // Global containers, not part of any workspace
        for child in container.children {
            child.unbindFromParent()
        }
    }
    check(Workspace.get(byName: "setUpWorkspacesForTests").focusWorkspace())
    Workspace.garbageCollectUnusedWorkspaces()
    check(focus.workspace.isEffectivelyEmpty)
    check(focus.workspace === Workspace.all.singleOrNil(), Workspace.all.map(\.description).joined(separator: ", "))
    check(mainMonitorInfo.setActiveWorkspace(focus.workspace))

    TestApp.shared.focusedWindow = nil
    TestApp.shared.windows = []
    appForTests = nil

    global_layoutForNextDetectedWindow = nil
    _prevFocusedWorkspaceName = nil
    resetFocusHistoryForTests()
    lastKnownNativeFocusedWindowId = nil
    activeMode = mainModeId
    TrayMenuModel.shared.isEnabled = true
    currentlyManipulatedWithMouseWindowId = nil
}

extension ParsedCmd {
    var errorOrNil: String? {
        return switch self {
            case .failure(let e): e.msg
            case .cmd, .help: nil
        }
    }

    var failureOrNil: CmdParsingFailure? {
        return switch self {
            case .failure(let failure): failure
            case .cmd, .help: nil
        }
    }

    var helpOrNil: String? {
        return switch self {
            case .help(let help): help
            case .cmd, .failure: nil
        }
    }

    var cmdOrDie: T { cmdOrNil ?? dieT("\(self)") }
}

extension Result {
    var failureOrNil: Failure? {
        return switch self {
            case .failure(let failure): failure
            case .success: nil
        }
    }
}

/// The arguments of `raw` if it parses as a single command with arguments of type `T`, nil otherwise
func parsedArgs<T: CmdArgs>(_ raw: String, as _: T.Type) -> T? {
    guard case .cmd(.cmd(let command)) = parseCommand(raw) else { return nil }
    return command.args as? T
}

func testParseCommandFail(
    _ command: String,
    msg expectedMsg: String,
    exitCode expectedExitCode: Int32 = 2,
    fileID: String = #fileID,
    filePath: StaticString = #filePath,
    line: Int = #line,
    column: Int = #column,
) {
    let parsed = parseCommand(command)
    switch parsed {
        case .cmd(let command): fail("\(command) isn't supposed to be parcelable", fileID: fileID, filePath: filePath, line: line, column: column)
        case .help: fail("'\(command)' isn't supposed to be parsed as help", fileID: fileID, filePath: filePath, line: line, column: column)
        case .failure(let failure):
            assertEquals(failure, .init(expectedMsg, expectedExitCode), fileID: fileID, filePath: filePath, line: line, column: column)
    }
}

/// Runs `command` and checks its exit code, and also its stdout and stderr when they are given
@MainActor
@discardableResult
func assertRun(
    _ command: String,
    env: CmdEnv = .defaultEnv,
    stdin: String = "",
    exitCode: Int32,
    stdout: [String]? = nil,
    stderr: [String]? = nil,
    fileID: String = #fileID,
    filePath: StaticString = #filePath,
    line: Int = #line,
    column: Int = #column,
) async -> CmdResult {
    let result = await parseCommand(command).cmdOrDie.run(env, CmdStdin(stdin))
    assertEquals(result.exitCode.rawValue, exitCode, additionalMsg: "exit code of '\(command)'", fileID: fileID, filePath: filePath, line: line, column: column)
    if let stdout {
        assertEquals(result.stdout, stdout, additionalMsg: "stdout of '\(command)'", fileID: fileID, filePath: filePath, line: line, column: column)
    }
    if let stderr {
        assertEquals(result.stderr, stderr, additionalMsg: "stderr of '\(command)'", fileID: fileID, filePath: filePath, line: line, column: column)
    }
    return result
}

extension WorkspaceCmdArgs {
    init(target: WorkspaceTarget, autoBackAndForth: Bool? = nil, wrapAround: Bool? = nil) {
        self = WorkspaceCmdArgs(rawArgs: [])
        self.target = .initialized(target)
        self._autoBackAndForth = autoBackAndForth
        self._wrapAround = wrapAround
    }
}

extension MoveNodeToWorkspaceCmdArgs {
    init(target: WorkspaceTarget) {
        self = MoveNodeToWorkspaceCmdArgs(rawArgs: [])
        self.target = .initialized(target)
    }

    init(workspace: String) {
        self = MoveNodeToWorkspaceCmdArgs(rawArgs: [])
        self.target = .initialized(.direct(.parse(workspace).getOrDie()))
    }
}

extension HotkeyBinding {
    init(_ modifiers: NSEvent.ModifierFlags, _ keyCode: Key, _ commands: Shell<any Command>) {
        let descriptionWithKeyNotation = modifiers.isEmpty
            ? keyCode.toString()
            : modifiers.toString() + "-" + keyCode.toString()
        self.init(modifiers, keyCode, commands, descriptionWithKeyNotation: descriptionWithKeyNotation)
    }
}

extension FocusCommand {
    static func new(direction: CardinalDirection) -> FocusCommand {
        FocusCommand(args: FocusCmdArgs(rawArgs: [], cardinalOrDfsDirection: .direction(direction)))
    }
}

func parseCommand(_ raw: String) -> ParsedCmd<Shell<any Command>> { parseCommand(raw, allowExecAndForget: true, allowEval: true) }
