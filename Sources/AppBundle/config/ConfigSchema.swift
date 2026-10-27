import Common
import OrderedCollections

private let configVersionKey = "config-version"
private let keyMappingKey = "key-mapping"
private let modeKey = "mode"
private let persistentWorkspacesKey = "persistent-workspaces"

// For every new config option you add, think:
// 1. Does it make sense to have different value
// 2. Prefer commands and commands flags over toml options if possible
private let rootFields: [String: Field<Config>] = [
    configVersionKey: .ignored(),

    "after-login-command": .ignored { raw, path, d in
        if raw.asArrayOrNil?.isEmpty != true {
            d.error(path, "after-login-command is deprecated since AeroSpace 0.19.0. https://github.com/nikitabobko/AeroSpace/issues/1482")
        }
    },
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
    persistentWorkspacesKey: Field(\.persistentWorkspaces, decodePersistentWorkspaces),
    "exec-on-workspace-change": Field(\.execOnWorkspaceChange, decodeStringArray),
    "exec": Field(\.execConfig, decodeExecConfig),

    keyMappingKey: .ignored(),
    modeKey: .ignored(),

    "gaps": Field(\.gaps, gapsFields),
    "focus-follows-mouse": Field(\.focusFollowsMouse, ["enabled": Field(\.enabled, decodeBool)]),
    "workspace-to-monitor-force-assignment": Field(\.workspaceToMonitorForceAssignment, decodeWorkspaceToMonitorAssignment),
    "on-window-detected": Field(\.onWindowDetected, decodeWindowRules),

    // Deprecated
    "non-empty-workspaces-root-containers-layout-on-startup": .ignored { raw, path, d in
        if let layout = decodeString(raw, path, &d), layout != "smart" {
            d.error(path, "'non-empty-workspaces-root-containers-layout-on-startup' is deprecated. Please drop it from your config")
        }
    },
    "indent-for-nested-containers-with-the-same-orientation": .ignored { _, path, d in
        d.error(path, "Deprecated. Please drop it from the config. See https://github.com/nikitabobko/AeroSpace/issues/96")
    },
]

struct ParseConfigResult {
    let config: Config
    let diagnostics: Diagnostics

    var errors: [ConfigParseDiagnostic] { diagnostics.errors }
    var warnings: [ConfigParseDiagnostic] { diagnostics.warnings }
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
    // The order is pinned: config-version, the sorted root keys, key-mapping, then mode (bindings resolve through key-mapping)
    config.configVersion = root[configVersionKey].flatMap { decodeConfigVersion($0, .rootKey(configVersionKey), &d) } ?? .min
    decodeTable(.dict(root), into: &config, rootFields, .emptyRoot, &d)
    if let raw = root[keyMappingKey] {
        decodeTable(raw, into: &config.keyMapping, keyMappingFields, .rootKey(keyMappingKey), &d)
    }
    if let raw = root[modeKey] {
        config.modes = decodeModes(raw, .rootKey(modeKey), config.keyMapping.resolve(), &d)
    }

    if config.configVersion <= ._1 {
        if root.keys.contains(persistentWorkspacesKey) {
            d.error(.rootKey(persistentWorkspacesKey), "This config option is only available since 'config-version = 2'")
        }
        config.persistentWorkspaces = implicitPersistentWorkspaces(config)
    }
    let bindingCommands = config.modes.values.lazy.flatMap { $0.bindings.values }.flatMap { $0.commands.flatten() }
    if config.enableNormalizationFlattenContainers && bindingCommands.contains(where: { $0 is SplitCommand }) {
        d.error(.emptyRoot, splitAndFlattenConflictMessage) // todo Make 'split' + flatten normalization prettier
    }
    if config.configVersion < .max {
        d.warning(.emptyRoot, "The current 'config-version = \(config.configVersion)' is outdated. " +
            "Please consider migrating to 'config-version = \(ConfigVersion.max)'. " +
            "See https://nikitabobko.github.io/AeroSpace/guide#config-version for the migration guide.")
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

/// Before 'config-version = 2', the workspaces mentioned in bindings and in the force assignment are persistent
private func implicitPersistentWorkspaces(_ config: Config) -> OrderedSet<String> {
    var result: OrderedSet<String> = []
    for mode in config.modes.values {
        for binding in mode.bindings.values {
            let commands = binding.commands.flatten()
            result.append(contentsOf: commands.filterIsInstance(of: WorkspaceCommand.self).compactMap { $0.args.target.val.workspaceNameOrNil()?.raw })
            result.append(contentsOf: commands.filterIsInstance(of: MoveNodeToWorkspaceCommand.self).compactMap { $0.args.target.val.workspaceNameOrNil()?.raw })
        }
    }
    result.append(contentsOf: config.workspaceToMonitorForceAssignment.keys)
    return result
}

private func decodeConfigVersion(_ raw: OrderedJson, _ path: ConfigBacktrace, _ d: inout Diagnostics) -> ConfigVersion? {
    decodeInt(raw, path, &d).flatMap {
        d.unwrap(ConfigVersion(rawValue: $0).toResult("config-version must be in [\(ConfigVersion.min), \(ConfigVersion.max)] range"), path)
    }
}

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
        return .newCompound(commands, Shell.seq)
    } else {
        d.typeMismatch(path, expected: [.string, .array], actual: raw)
        return .empty
    }
}

func parseCommandForConfig(_ raw: String, allowExecAndForget: Bool, _ path: ConfigBacktrace, _ d: inout Diagnostics) -> Shell<any Command> {
    switch parseCommand(raw, allowExecAndForget: allowExecAndForget, allowEval: false) {
        case .cmd(let shell): return shell
        case .help(let msg): d.error(path, msg)
        case .failure(let failure): d.error(path, failure.msg)
    }
    return .empty
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
        d.typeMismatch(path, expected: [.string, .int], actual: raw)
        return nil
    }
    return d.unwrap(parseMonitorDescription(string), path)
}
