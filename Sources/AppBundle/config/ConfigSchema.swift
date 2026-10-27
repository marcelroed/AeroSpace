import Common
import OrderedCollections

private let keyMappingKey = "key-mapping"
private let modeKey = "mode"

// For every new config option you add, think:
// 1. Does it make sense to have different value
// 2. Prefer commands and commands flags over toml options if possible
private let rootFields: [String: Field<Config>] = [
    "after-startup-command": Field(\.afterStartupCommand, decodeShellOfCommands),

    "on-focus-changed": Field(\.onFocusChanged, decodeShellOfCommands),
    "on-mode-changed": Field(\.onModeChanged, decodeShellOfCommands),
    "on-focused-monitor-changed": Field(\.onFocusedMonitorChanged, decodeShellOfCommands),

    "enable-normalization-flatten-containers": Field(\.enableNormalizationFlattenContainers, decodeBool),
    "enable-normalization-opposite-orientation-for-nested-containers": Field(\.enableNormalizationOppositeOrientationForNestedContainers, decodeBool),

    "default-root-container-layout": Field(\.defaultRootContainerLayout, decodeParsed { $0.parseLayout().toResult("Can't parse layout '\($0)'") }),
    "default-root-container-orientation": Field(\.defaultRootContainerOrientation, decodeParsed {
        DefaultContainerOrientation(rawValue: $0).toResult("Can't parse default container orientation '\($0)'")
    }),

    "start-at-login": Field(\.startAtLogin, decodeBool),
    "auto-reload-config": Field(\.autoReloadConfig, decodeBool),
    "automatically-unhide-macos-hidden-apps": Field(\.automaticallyUnhideMacosHiddenApps, decodeBool),
    "accordion-padding": Field(\.accordionPadding, decodeInt),
    "persistent-workspaces": Field(\.persistentWorkspaces, decodePersistentWorkspaces),
    "exec-on-workspace-change": Field(\.execOnWorkspaceChange, decodeStringArray),
    "exec": Field(\.execConfig, decodeExecConfig),

    keyMappingKey: .ignored(),
    modeKey: .ignored(),

    "gaps": Field(\.gaps, gapsFields),
    "focus-follows-mouse": Field(\.focusFollowsMouse, ["enabled": Field(\.enabled, decodeBool)]),
    "workspace-to-monitor-force-assignment": Field(\.workspaceToMonitorForceAssignment, decodeWorkspaceToMonitorAssignment),
    "on-window-detected": Field(\.onWindowDetected, decodeWindowRules),
]

struct ParseConfigResult {
    let config: Config
    let diagnostics: Diagnostics

    var errors: [ConfigParseDiagnostic] { diagnostics.errors }
    var allowReloadConfig: Bool { !diagnostics.isFatal }

    static func fatal(_ message: String) -> Self {
        var d = Diagnostics()
        d.fatal(message)
        return ParseConfigResult(config: Config(), diagnostics: d)
    }
}

func parseConfig(_ rawToml: String) -> ParseConfigResult {
    var d = Diagnostics()
    let root = decodeTomlRoot(rawToml, &d)
    var config = Config()
    // The order is pinned: the sorted root keys, key-mapping, then mode (bindings resolve through key-mapping)
    decodeTable(.dict(root), into: &config, rootFields, .emptyRoot, &d)
    if let raw = root[keyMappingKey] {
        decodeTable(raw, into: &config.keyMapping, keyMappingFields, .rootKey(keyMappingKey), &d)
    }
    if let raw = root[modeKey] {
        config.modes = decodeModes(raw, .rootKey(modeKey), config.keyMapping.resolve(), &d)
    }
    let bindingCommands = config.modes.values.lazy.flatMap { $0.bindings.values }.flatMap { $0.commands.flatten() }
    if config.enableNormalizationFlattenContainers && bindingCommands.contains(where: { $0 is SplitCommand }) {
        d.error(.emptyRoot, splitAndFlattenConflictMessage) // todo Make 'split' + flatten normalization prettier
    }
    return ParseConfigResult(config: config, diagnostics: d)
}

private let splitAndFlattenConflictMessage = """
    The config contains:
    1. usage of 'split' command
    2. enable-normalization-flatten-containers = true
    These two settings don't play nicely together. 'split' command has no effect when enable-normalization-flatten-containers is enabled.

    My recommendation: keep the normalizations enabled, and prefer 'join-with' over 'split'.
    """

private let decodePersistentWorkspaces: Decode<OrderedSet<String>> = { raw, path, d in
    guard let array = decodeStringArray(raw, path, &d) else { return nil }
    let set = OrderedSet(array)
    if set.count == array.count { return set }
    d.error(path, "Contains duplicated workspace names")
    return nil
}

/// Stops at the first element that isn't a string
private let decodeStringArray: Decode<[String]> = { raw, path, d in
    guard let array = decodeArray(raw, path, &d) else { return nil }
    var result: [String] = []
    for (index, elem) in array.enumerated() {
        guard let string = decodeString(elem, path + .index(index), &d) else { return nil }
        result.append(string)
    }
    return result
}

/// A command string, or an array of command strings that run in sequence. An unusable value becomes the empty command
let decodeShellOfCommands: Decode<Shell<any Command>> = { raw, path, d in
    if let string = raw.asStringOrNil {
        return parseCommandForConfig(string, allowExecAndForget: true, path, &d)
    } else if let array = raw.asArrayOrNil {
        let commands = array.enumerated().compactMap { index, elem in
            decodeString(elem, path + .index(index), &d).map { parseCommandForConfig($0, allowExecAndForget: true, path + .index(index), &d) }
        }
        return .compound(.seq, commands)
    } else {
        d.typeMismatch(path, expected: .string, .array, actual: raw)
        return .empty
    }
}

func parseCommandForConfig(_ raw: String, allowExecAndForget: Bool, _ path: ConfigBacktrace, _ d: inout Diagnostics) -> Shell<any Command> {
    switch parseCommand(raw, allowExecAndForget: allowExecAndForget, allowEval: false) {
        case .cmd(let shell): return shell
        case .help(let msg): d.error(path, msg)
        case .failure(let failure): d.error(path, withoutErrorPrefixes(failure.msg))
    }
    return .empty
}

/// The config diagnostic has its own "[ERROR]": drop the "ERROR: " prefixes and the continuation indent of `joinErrors`
private func withoutErrorPrefixes(_ msg: String) -> String {
    msg.split(separator: "\n", omittingEmptySubsequences: false)
        .map { line in line.starts(with: "ERROR: ") ? line.dropFirst(7) : line.trimmingPrefix("       ") }
        .joined(separator: "\n")
}

private let decodeWorkspaceToMonitorAssignment: Decode<[String: [MonitorDescription]]> = { raw, path, d in
    guard let table = decodeDict(raw, path, &d) else { return nil }
    var result: [String: [MonitorDescription]] = [:]
    for (workspace, raw) in table {
        let path = path + .key(workspace)
        result[workspace] = if let array = raw.asArrayOrNil {
            array.enumerated().compactMap { index, raw in decodeMonitorDescription(raw, path + .index(index), &d) }
        } else {
            decodeMonitorDescription(raw, path, &d).map { [$0] } ?? []
        }
    }
    return result
}

private func decodeMonitorDescription(_ raw: OrderedJson, _ path: ConfigBacktrace, _ d: inout Diagnostics) -> MonitorDescription? {
    guard let string = raw.asStringOrNil ?? raw.asIntOrNil.map({ String($0) }) else {
        d.typeMismatch(path, expected: .string, .int, actual: raw)
        return nil
    }
    return d.unwrap(parseMonitorDescription(string), path)
}
