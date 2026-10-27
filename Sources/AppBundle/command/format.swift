import Common
import Foundation

/// An interpolation variable of `--format`, `echo` and `test`: `%{name}`
nonisolated enum FormatVar: String, CaseIterable, Sendable {
    case windowId = "window-id"
    case windowIsFullscreen = "window-is-fullscreen"
    case windowTitle = "window-title"
    case windowLayout = "window-layout" // An alias for windowParentContainerLayout
    case windowParentContainerLayout = "window-parent-container-layout"

    case workspace = "workspace"
    case workspaceIsFocused = "workspace-is-focused"
    case workspaceIsVisible = "workspace-is-visible"
    case workspaceRootContainerLayout = "workspace-root-container-layout"

    case appBundleId = "app-bundle-id"
    case appName = "app-name"
    case appPid = "app-pid"
    case appExecPath = "app-exec-path"
    case appBundlePath = "app-bundle-path"

    case monitorId = "monitor-id"
    case monitorAppKitNsScreenScreensId = "monitor-appkit-nsscreen-screens-id"
    case monitorName = "monitor-name"
    case monitorIsMain = "monitor-is-main"

    // Formatting, not about an object
    case rightPadding = "right-padding"
    case newline = "newline"
    case tab = "tab"

    /// The kind of object the variable describes, nil for the formatting variables
    var subject: FormatSubject? {
        switch self {
            case .windowId, .windowIsFullscreen, .windowTitle, .windowLayout, .windowParentContainerLayout: .window
            case .workspace, .workspaceIsFocused, .workspaceIsVisible, .workspaceRootContainerLayout: .workspace
            case .appBundleId, .appName, .appPid, .appExecPath, .appBundlePath: .app
            case .monitorId, .monitorAppKitNsScreenScreensId, .monitorName, .monitorIsMain: .monitor
            case .rightPadding, .newline, .tab: nil
        }
    }
}

nonisolated enum FormatSubject: CaseIterable, Sendable {
    case window, workspace, app, monitor

    /// A window also has the variables of its workspace, monitor and app; a workspace those of its monitor
    var availableVars: [FormatVar] {
        let subjects: [FormatSubject] = switch self {
            case .window: [.window, .workspace, .monitor, .app]
            case .workspace: [.workspace, .monitor]
            case .app, .monitor: [self]
        }
        let subjectVars: [FormatVar] = subjects.flatMap { (subject: FormatSubject) -> [FormatVar] in FormatVar.allCases.filter { $0.subject == subject } }
        return subjectVars + FormatVar.allCases.filter { $0.subject == nil }
    }
}

typealias FormatToken = InterToken<FormatVar>

/// Parses the `%{var}` interpolations of `raw`
nonisolated func parseFormat(_ raw: String) throws(CmdParseError) -> [FormatToken] {
    return try raw.rawInterpolationTokens(interpolationChar: "%").map { (token) throws(CmdParseError) in
        switch token {
            case .literal(let literal): .literal(literal)
            case .interVar(let name): .interVar(try parseEnum(name))
        }
    }
}

/// How a list-* command prints its objects: `--count`, or `--format` and `--json`
nonisolated enum ListOutput: Equatable, Sendable {
    case count
    case lines([FormatToken])
    /// The format holds only variables and spaces
    case json([FormatToken])

    var format: [FormatToken] {
        switch self {
            case .count: []
            case .lines(let format), .json(let format): format
        }
    }

    /// The output options as they appear in a command's option loop
    struct Options {
        private var count = false
        private var json = false
        private var format: [FormatToken]? = nil

        init() {}

        /// Takes `option` if it is an output option
        mutating func take(_ option: String, _ a: inout ArgCursor, _ subject: FormatSubject) throws(CmdParseError) -> Bool {
            switch option {
                case "--count": count = true
                case "--json": json = true
                case "--format":
                    let values = subject.availableVars.map(\.rawValue).joined(separator: "\n").prefixLines(with: "  ")
                    guard let raw = a.valueOrNil() else { throw "<output-format> is mandatory. Possible values:\n\(values)" }
                    do {
                        format = try parseFormat(raw)
                    } catch {
                        throw "Failed to parse <output-format>. \(error.message)"
                    }
                default: return false
            }
            return true
        }

        func build(defaultFormat: [FormatToken]) throws(CmdParseError) -> ListOutput {
            if count {
                if format != nil { throw .conflicting("--count", "--format") }
                if json { throw .conflicting("--count", "--json") }
                return .count
            }
            guard json else { return .lines(format ?? defaultFormat) }
            for token in format ?? [] {
                switch token {
                    case .interVar(.rightPadding):
                        throw "%{right-padding} interpolation variable is not allowed when --json is used"
                    case .literal(let literal) where literal.contains(where: { $0 != " " }):
                        throw "Only interpolation variables and spaces are allowed in '--format' when '--json' is used"
                    case .interVar, .literal: break
                }
            }
            return .json(format ?? defaultFormat)
        }
    }

    @MainActor func print(_ list: [AeroObj], _ cx: CmdContext) throws(CmdFail) {
        do {
            switch self {
                case .count: cx.out("\(list.count)")
                case .lines(let format): cx.out(try list.format(format))
                case .json(let format): cx.out(try list.formatToJson(format))
            }
        } catch {
            throw CmdFail(error.description)
        }
    }
}

struct WindowWithPrefetchedTitle {
    let window: Window
    let title: String?

    private init(window: Window, title: String?) {
        self.window = window
        self.title = title
    }

    /// A window that closed meanwhile has the empty title
    static func resolveWindow(_ window: Window, for format: [FormatToken]) async -> Self {
        let title = format.contains(.interVar(.windowTitle)) ? await world.platform.title(window.windowId) ?? "" : nil
        return .init(window: window, title: title)
    }

    static func forTest(window: Window, title: String?) -> Self {
        .init(window: window, title: title)
    }
}

enum AeroObj {
    case window(WindowWithPrefetchedTitle)
    case workspace(Workspace)
    case app(AppInfo)
    case monitor(MonitorInfo)

    var subject: FormatSubject {
        switch self {
            case .window: .window
            case .workspace: .workspace
            case .app: .app
            case .monitor: .monitor
        }
    }
}

extension AeroObj {
    /// The line of the object: the cells end at each %{right-padding}
    fileprivate func cells(_ format: [FormatToken]) throws(FormatVarExpansionError) -> [Cell] {
        var line: [Cell] = []
        var curCell: String = ""
        for token in format {
            switch token {
                case .interVar(.rightPadding):
                    line.append(Cell(value: curCell, rightPadding: true))
                    curCell = ""
                case .literal(let literal): curCell += literal
                case .interVar(let formatVar): curCell += try formatVar.expand(self).toString()
            }
        }
        line.append(Cell(value: curCell, rightPadding: false))
        return line
    }

    /// The object on its own line, `echo` and `test`
    func format(_ format: [FormatToken]) throws(FormatVarExpansionError) -> String {
        try cells(format).map(\.value).joined()
    }
}

extension [AeroObj] {
    /// One line per object. The cells before each %{right-padding} are padded to the width of their column
    func format(_ format: [FormatToken]) throws(FormatVarExpansionError) -> [String] {
        try map { (obj) throws(FormatVarExpansionError) in try obj.cells(format) }
            .transposed()
            .map { column in
                let columnWidth = column.map { $0.value.count }.max().orDie()
                return column.map {
                    $0.rightPadding
                        ? $0.value + String(repeating: " ", count: columnWidth - $0.value.count)
                        : $0.value
                }
            }
            .transposed()
            .map { line in line.joined(separator: "") }
    }

    /// An array of objects with a key per variable. %{right-padding} (of the default formats) is skipped
    func formatToJson(_ format: [FormatToken]) throws(FormatVarExpansionError) -> String {
        var list: [[String: Primitive]] = []
        for obj in self {
            var rawObj: [String: Primitive] = [:]
            for case .interVar(let formatVar) in format where formatVar != .rightPadding {
                rawObj[formatVar.rawValue] = try formatVar.expand(obj)
            }
            list.append(rawObj)
        }
        guard let json = JSONEncoder.aeroSpaceDefault.encodeToString(list) else { throw .other("Can't encode '\(list)' to JSON") }
        return json
    }
}

private struct Cell {
    let value: String
    let rightPadding: Bool
}

enum Primitive: Encodable {
    case bool(Bool)
    case int(Int64)
    case string(String)

    enum Kind: String {
        case bool = "Bool"
        case int = "Int"
        case string = "String"
    }

    var kind: Kind {
        switch self {
            case .bool: .bool
            case .int: .int
            case .string: .string
        }
    }

    func toString() -> String {
        switch self {
            case .bool(let x): x.description
            case .int(let x): x.description
            case .string(let x): x
        }
    }

    func encode(to encoder: any Encoder) throws {
        let value: Encodable = switch self {
            case .bool(let x): x
            case .int(let x): x
            case .string(let x): x
        }
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    static func int(_ int: UInt32) -> Self { .int(Int64(int)) }
    static func int(_ int: Int32) -> Self { .int(Int64(int)) }
    static func int(_ int: Int) -> Self { .int(Int64(int)) }
}

enum FormatVarExpansionError: Error, CustomStringConvertible {
    /// The variable is about another kind of object
    case unavailable(FormatVar, FormatSubject)
    case other(String)

    var description: String {
        switch self {
            case .unavailable(let formatVar, let subject):
                "Unknown interpolation variable '\(formatVar.rawValue)'. " +
                    "Possible values:\n\(subject.availableVars.map(\.rawValue).joined(separator: "\n").prefixLines(with: "  "))"
            case .other(let msg): msg
        }
    }

    /// The error message that `echo` and `test` report: their object is the focused window, or the workspace if
    /// there is no window
    var cmdErrorMessage: String {
        switch self {
            case .unavailable: noWindowIsFocused
            case .other: description
        }
    }
}

extension FormatVar {
    func expand(_ obj: AeroObj) throws(FormatVarExpansionError) -> Primitive {
        switch (obj, subject) {
            case (_, nil):
                switch self {
                    case .newline: return .string("\n")
                    case .tab: return .string("\t")
                    default: throw .other("'\(rawValue)' interpolation variable cannot be expanded")
                }
            case (.window(let w), .workspace):
                guard let workspace = w.window.nodeWorkspace else { return .string("NULL-WORKSPACE") }
                return try expand(.workspace(workspace))
            case (.window(let w), .monitor):
                guard let monitor = w.window.nodeMonitor else { return .string("NULL-MONITOR") }
                return try expand(.monitor(monitor))
            case (.window(let w), .app):
                return try expand(.app(w.window.app))
            case (.workspace(let ws), .monitor):
                return try expand(.monitor(ws.workspaceMonitor))
            case (.window(let w), .window):
                switch self {
                    case .windowId: return .int(w.window.windowId.raw)
                    case .windowIsFullscreen: return .bool(w.window.isFullscreen)
                    case .windowTitle: return .string(w.title.orDie("Title wasn't prefetched"))
                    case .windowLayout, .windowParentContainerLayout: return try layout(of: w.window)
                    default: throw .unavailable(self, obj.subject)
                }
            case (.workspace(let w), .workspace):
                switch self {
                    case .workspace: return .string(w.name)
                    case .workspaceIsVisible: return .bool(w.isVisible)
                    case .workspaceIsFocused: return .bool(focus.workspace == w)
                    case .workspaceRootContainerLayout: return .string(layoutString(w.rootLayout))
                    default: throw .unavailable(self, obj.subject)
                }
            case (.monitor(let m), .monitor):
                switch self {
                    case .monitorId: return .int(m.monitorId_oneBased)
                    case .monitorAppKitNsScreenScreensId: return .int(m.monitorAppKitNsScreenScreensId)
                    case .monitorName: return .string(m.name)
                    case .monitorIsMain: return .bool(m.isMain)
                    default: throw .unavailable(self, obj.subject)
                }
            case (.app(let a), .app):
                switch self {
                    case .appBundleId: return .string(a.bundleId ?? "NULL-APP-BUNDLE-ID")
                    case .appName: return .string(a.name ?? "NULL-APP-NAME")
                    case .appPid: return .int(a.pid)
                    case .appExecPath: return .string(a.execPath ?? "NULL-APP-EXEC-PATH")
                    case .appBundlePath: return .string(a.bundlePath ?? "NULL-APP-BUNDLE-PATH")
                    default: throw .unavailable(self, obj.subject)
                }
            case (.workspace, _), (.app, _), (.monitor, _):
                throw .unavailable(self, obj.subject)
        }
    }
}

private func layoutString(_ tc: TilingContainer) -> String {
    layoutString((tc.layout, tc.orientation))
}

private func layoutString(_ kind: (layout: Layout, orientation: Orientation)) -> String {
    let layout: LayoutCommand.LayoutDescription = switch kind {
        case (.tiles, .h): .h_tiles
        case (.tiles, .v): .v_tiles
        case (.accordion, .h): .h_accordion
        case (.accordion, .v): .v_accordion
    }
    return layout.rawValue
}

private func layout(of w: Window) throws(FormatVarExpansionError) -> Primitive {
    switch w.placement {
        case nil: throw .other("NULL-PARENT")
        case .tiling(let tc): .string(layoutString(tc))
        case .floating: .string(LayoutCommand.LayoutDescription.floating.rawValue)
        case .macosFullscreen: .string("macos_native_fullscreen")
        case .macosHiddenApp: .string("macos_native_window_of_hidden_app")
        case .macosMinimized: .string("macos_native_minimized")
        case .macosPopup: .string("NULL-WINDOW-LAYOUT")
    }
}
