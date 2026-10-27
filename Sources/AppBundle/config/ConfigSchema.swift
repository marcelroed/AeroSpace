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

    "default-root-container-layout": Field(\.defaultRootContainerLayout, decodeRawValue("layout")),
    "default-root-container-orientation": Field(\.defaultRootContainerOrientation, decodeRawValue("default container orientation")),

    "start-at-login": Field(\.startAtLogin, decodeBool),
    "auto-reload-config": Field(\.autoReloadConfig, decodeBool),
    "automatically-unhide-macos-hidden-apps": Field(\.automaticallyUnhideMacosHiddenApps, decodeBool),
    "accordion-padding": Field(\.accordionPadding, decodeInt),
    "persistent-workspaces": Field(\.persistentWorkspaces, decodePersistentWorkspaces),
    "exec-on-workspace-change": Field(\.execOnWorkspaceChange, decodeStringArray),
    "exec": Field(\.execConfig, decodeExecConfig),

    keyMappingKey: .ignored,
    modeKey: .ignored,

    "gaps": Field(\.gaps, gapsFields),
    "focus-follows-mouse": Field(\.focusFollowsMouse, ["enabled": Field(\.enabled, decodeBool)]),
    "workspace-to-monitor-force-assignment": Field(\.workspaceToMonitorForceAssignment, decodeWorkspaceToMonitorAssignment),
    "on-window-detected": Field(\.onWindowDetected, decodeWindowRules),
]

enum ParseConfigResult {
    /// An ambiguous or unreadable file, or a TOML syntax error: there is no config to apply
    case fatal(String)
    /// The keys with errors keep their defaults. The config is applied even if there are errors
    case parsed(Config, errors: [ConfigParseDiagnostic])

    var errors: [ConfigParseDiagnostic] {
        switch self {
            case .fatal(let message): [ConfigParseDiagnostic(.emptyRoot, message)]
            case .parsed(_, let errors): errors
        }
    }
}

func parseConfig(_ rawToml: String) -> ParseConfigResult {
    var d = Diagnostics()
    let root: OrderedJson.JsonDict
    do {
        root = try decodeTomlRoot(rawToml, &d)
    } catch {
        return .fatal(error.description)
    }
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
    return .parsed(config, errors: d.errors)
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

/// A command string, or an array of command strings that run in sequence. Unusable if any element is
let decodeShellOfCommands: Decode<Shell<any Command>> = { raw, path, d in
    if let string = raw.asStringOrNil {
        return parseCommandForConfig(string, allowExecAndForget: true, path, &d)
    }
    guard let array = raw.asArrayOrNil else {
        d.typeMismatch(path, expected: .string, .array, actual: raw)
        return nil
    }
    let commands = array.enumerated().map { index, elem in
        decodeString(elem, path + .index(index), &d).flatMap { parseCommandForConfig($0, allowExecAndForget: true, path + .index(index), &d) }
    }
    return allOrNil(commands).map { .compound(.seq, $0) }
}

/// `nil` if `raw` doesn't parse
func parseCommandForConfig(_ raw: String, allowExecAndForget: Bool, _ path: ConfigBacktrace, _ d: inout Diagnostics) -> Shell<any Command>? {
    do {
        return try parseShell(raw, allowExecAndForget: allowExecAndForget, allowEval: false)
    } catch {
        d.error(path, error.message)
        return nil
    }
}

/// The monitor patterns of each workspace, tried in order. A workspace with an unusable pattern is dropped,
/// and so is not force-assigned. `w = []` is valid: it doesn't force-assign `w` either
private let decodeWorkspaceToMonitorAssignment: Decode<[String: [MonitorDescription]]> = { raw, path, d in
    guard let table = decodeDict(raw, path, &d) else { return nil }
    var result: [String: [MonitorDescription]] = [:]
    for (workspace, raw) in table {
        let path = path + .key(workspace)
        result[workspace] = if let array = raw.asArrayOrNil {
            allOrNil(array.enumerated().map { index, raw in decodeMonitorDescription(raw, path + .index(index), &d) })
        } else {
            decodeMonitorDescription(raw, path, &d).map { [$0] }
        }
    }
    return result
}

private func decodeMonitorDescription(_ raw: OrderedJson, _ path: ConfigBacktrace, _ d: inout Diagnostics) -> MonitorDescription? {
    guard let string = raw.asStringOrNil ?? raw.asIntOrNil.map({ String($0) }) else {
        d.typeMismatch(path, expected: .string, .int, actual: raw)
        return nil
    }
    return d.parsed(path) { () throws(CmdParseError) in try parseMonitorDescription(string) }
}
