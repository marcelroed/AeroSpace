import AppKit
import Common

struct LayoutCommand: nonisolated Command {
    nonisolated enum LayoutDescription: String, CaseIterable, Equatable, Sendable {
        case accordion, tiles
        case horizontal, vertical
        case h_accordion, v_accordion, h_tiles, v_tiles
        case tiling, floating

        fileprivate var isTilingOrFloating: Bool {
            switch self {
                case .floating, .tiling: true
                case .accordion, .h_accordion, .h_tiles, .horizontal, .tiles, .v_accordion, .v_tiles, .vertical: false
            }
        }

        /// The deprecated `list` names are aliases of `tiles`
        fileprivate static func parse(_ raw: String) throws(CmdParseError) -> Self {
            switch raw {
                case "list": return .tiles
                case "h_list": return .h_tiles
                case "v_list": return .v_tiles
                default:
                    guard let it = Self(rawValue: raw) else { throw "Can't parse '\(raw)'\nPossible values: \(unionLiteral)" }
                    return it
            }
        }
    }

    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    /// Not empty
    var toggleBetween: [LayoutDescription]
    var root = false
    var failIfNoop = false
    var forNextDetectedWindow = false
    var windowId: UInt32? = nil
    var workspace: WorkspaceName? = nil

    static let rootFlagIncompatibilityMsg = "layout command: --root and tiling|floating are incompatible"
    static let forNextDetectedWindowFlagIncompatibilityMsg =
        "layout command: --for-next-detected-window allows only one tiling|floating <target-layout> argument"

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var result = Self(toggleBetween: [])
        while let option = try a.nextOption() {
            switch option {
                case "--window-id": result.windowId = try a.windowId(of: option)
                case "--workspace": result.workspace = try a.workspace(of: option)
                case "--root": result.root = true
                case "--fail-if-noop": result.failIfNoop = true
                case "--for-next-detected-window": result.forNextDetectedWindow = true
                default: throw .unknownOption(option)
            }
        }
        result.toggleBetween = try a.allPositionals().map(LayoutDescription.parse)
        if result.toggleBetween.isEmpty { throw "Argument '\(LayoutDescription.unionLiteral)' is mandatory" }
        if result.windowId != nil && result.workspace != nil { throw .conflicting("--window-id", "--workspace") }
        if result.forNextDetectedWindow {
            // todo introduce a flagsAllowlist primitive
            for (option, isSet) in [
                ("--fail-if-noop", result.failIfNoop),
                ("--root", result.root),
                ("--window-id", result.windowId != nil),
                ("--workspace", result.workspace != nil),
            ] where isSet {
                throw .conflicting("--for-next-detected-window", option)
            }
        }
        if result.root && result.toggleBetween.contains(where: \.isTilingOrFloating) { throw .invalid(rootFlagIncompatibilityMsg) }
        if result.forNextDetectedWindow && result.toggleBetween.singleOrNil()?.isTilingOrFloating != true {
            throw .invalid(forNextDetectedWindowFlagIncompatibilityMsg)
        }
        if result.workspace != nil && !result.root { throw "--workspace flag requires using an explicit --root flag" }
        if result.failIfNoop && result.toggleBetween.count != 1 { throw "--fail-if-noop allows only one <target-layout> argument" }
        return result
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        if forNextDetectedWindow {
            guard let it = toggleBetween.singleOrNil() else { throw CmdFail(bugPrompt()) }
            world.layoutForNextDetectedWindow = it
            return
        }
        let target = try cx.target(windowId: windowId, workspace: workspace)

        let subject: LayoutSubject
        switch root ? nil : target.windowOrNil {
            case let window?:
                switch window.placement {
                    case .floating:
                        subject = .floatingWindow(window)
                    case .tiling(let it):
                        subject = .tilingContainer(it)
                    case .macosFullscreen,
                         .macosHiddenApp,
                         .macosMinimized:
                        let msg = "Can't change layout for macOS minimized, fullscreen windows or windows or hidden apps. " +
                            "This behavior is subject to change"
                        throw CmdFail(msg)
                    case nil, .macosPopup:
                        throw CmdFail(bugPrompt())
                }
            case nil:
                subject = .tilingContainer(target.workspace.rootTilingContainer)
        }

        let targetDescription = toggleBetween.first(where: { !subject.matches($0) })
            ?? toggleBetween.first.orDie()
        if subject.matches(targetDescription) {
            return try noop(cx, failIfNoop: failIfNoop, "Already in the requested \(targetDescription.rawValue) mode. " +
                "Tip: use --fail-if-noop to exit with non-zero code")
        }
        switch targetDescription {
            case .h_accordion, .v_accordion, .h_tiles, .v_tiles, .accordion, .tiles, .horizontal, .vertical:
                guard case .tilingContainer(let parent) = subject else { throw CmdFail("The window is non-tiling") }
                parent.layout = targetDescription.tilingLayout ?? parent.layout
                parent.changeOrientation(targetDescription.tilingOrientation ?? parent.orientation)
            case .tiling:
                guard case .floatingWindow(let window) = subject else { return } // Already tiling
                let workspace = window.nodeWorkspace // The floating container's workspace. Read it before the suspension point
                window.lastFloatingSize = (try? await window.getAxSize(.nonCancellable)) ?? window.lastFloatingSize
                guard let workspace else { throw CmdFail(bugPrompt()) }
                do {
                    try await window.relayoutWindow(on: workspace, .nonCancellable, forceTile: true)
                } catch {
                    throw CmdFail(bugPrompt())
                }
            case .floating:
                guard let window = target.windowOrNil else { throw CmdFail(noWindowIsFocused) }
                let workspace = target.workspace
                window.bindAsFloatingWindow(to: workspace)
                if let size = window.lastFloatingSize { window.setAxFrame(nil, size) }
        }
    }
}

/// What the layout command changes
private enum LayoutSubject {
    case tilingContainer(TilingContainer) // The window's tiling parent, or the workspace's root container
    case floatingWindow(Window)

    func matches(_ description: LayoutCommand.LayoutDescription) -> Bool {
        guard case .tilingContainer(let container) = self else { return description == .floating }
        return switch description {
            case .tiling: true
            case .floating: false
            case .h_accordion, .v_accordion, .h_tiles, .v_tiles, .accordion, .tiles, .horizontal, .vertical:
                container.layout == (description.tilingLayout ?? container.layout) &&
                    container.orientation == (description.tilingOrientation ?? container.orientation)
        }
    }
}

extension LayoutCommand.LayoutDescription {
    /// The layout that a tiling description requests. nil: keep the current one
    fileprivate var tilingLayout: Layout? {
        switch self {
            case .accordion, .h_accordion, .v_accordion: .accordion
            case .tiles, .h_tiles, .v_tiles: .tiles
            case .horizontal, .vertical, .tiling, .floating: nil
        }
    }

    /// The orientation that a tiling description requests. nil: keep the current one
    fileprivate var tilingOrientation: Orientation? {
        switch self {
            case .horizontal, .h_accordion, .h_tiles: .h
            case .vertical, .v_accordion, .v_tiles: .v
            case .accordion, .tiles, .tiling, .floating: nil
        }
    }
}

struct SplitCommand: nonisolated Command {
    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var arg: SplitArg
    var windowId: UInt32? = nil

    nonisolated enum SplitArg: String, CaseIterable, Sendable {
        case horizontal, vertical, opposite
    }

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var windowId: UInt32? = nil
        while let option = try a.nextOption() {
            switch option {
                case "--window-id": windowId = try a.windowId(of: option)
                default: throw .unknownOption(option)
            }
        }
        let result = Self(arg: try a.positional(), windowId: windowId)
        try a.end()
        return result
    }

    func run(_ cx: CmdContext) throws(CmdFail) {
        if config.enableNormalizationFlattenContainers {
            throw CmdFail("'split' has no effect when 'enable-normalization-flatten-containers' normalization enabled. My recommendation: keep the normalizations enabled, and prefer 'join-with' over 'split'.")
        }
        let window = try cx.window(windowId: windowId)
        switch window.placement {
            case .floating:
                // Nothing to do for floating and macOS native fullscreen windows
                throw CmdFail("Can't split floating windows")
            case .tiling(let parent):
                let orientation: Orientation = switch arg {
                    case .vertical: .v
                    case .horizontal: .h
                    case .opposite: parent.orientation.opposite
                }
                if parent.children.count == 1 {
                    parent.changeOrientation(orientation)
                } else {
                    let data = window.unbindFromParent()
                    let newParent = TilingContainer(
                        parent: parent,
                        weight: data.weight,
                        orientation,
                        .tiles,
                        index: data.index,
                    )
                    window.bind(to: newParent, index: 0)
                }
                return
            case .macosMinimized, .macosFullscreen, .macosHiddenApp:
                throw CmdFail("Can't split macos fullscreen, minimized windows and windows of hidden apps. This behavior may change in the future")
            case .macosPopup, nil:
                throw CmdFail(bugPrompt()) // Impossible
        }
    }
}

struct ResizeCommand: nonisolated Command {
    nonisolated enum Dimension: String, CaseIterable, Equatable, Sendable {
        case width, height, smart
        case smartOpposite = "smart-opposite"
    }

    nonisolated enum Units: Equatable, Sendable {
        case set(UInt)
        case add(UInt)
        case subtract(UInt)

        /// `[+|-]<number>`: exactly one optional sign
        static func parse(_ raw: String) throws(CmdParseError) -> Self {
            let digits = raw.starts(with: "+") || raw.starts(with: "-") ? raw.dropFirst() : raw[...]
            // UInt(...) accepts a sign too. Check the first char, so that the number has exactly one optional sign
            guard digits.first?.isNumber == true, let number = UInt(digits) else { throw "<number> argument must be a number" }
            return switch raw.first {
                case "+": .add(number)
                case "-": .subtract(number)
                default: .set(number)
            }
        }
    }

    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var dimension: Dimension
    var units: Units
    var windowId: UInt32? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var windowId: UInt32? = nil
        while let option = try a.nextOption() {
            switch option {
                case "--window-id": windowId = try a.windowId(of: option)
                default: throw .unknownOption(option)
            }
        }
        let dimension: Dimension = try parseEnum(a.positional("(smart|smart-opposite|width|height)"))
        let units = try Units.parse(a.positional("[+|-]<number>"))
        try a.end()
        return Self(dimension: dimension, units: units, windowId: windowId)
    }

    func run(_ cx: CmdContext) async throws(CmdFail) {
        let target = try cx.target(windowId: windowId)

        let candidates = target.windowOrNil?.parentsWithSelf
            .filter { ($0.parent as? TilingContainer)?.layout == .tiles }
            ?? []

        // All candidates have a TilingContainer parent, so for .smart, node is candidates.first
        let orientation: Orientation? = switch dimension {
            case .width: .h
            case .height: .v
            case .smart: (candidates.first?.parent as? TilingContainer)?.orientation
            case .smartOpposite: (candidates.first?.parent as? TilingContainer)?.orientation.opposite
        }
        let node = candidates.first(where: { ($0.parent as? TilingContainer)?.orientation == orientation })
        // node was picked by its parent's orientation, so parent.orientation == orientation
        guard let node, let parent = node.parent as? TilingContainer else {
            guard let window = target.windowOrNil else { throw CmdFail(noWindowIsFocused) }
            if window.isFloating {
                throw CmdFail("resize command doesn't support floating windows yet https://github.com/nikitabobko/AeroSpace/issues/9")
            }
            let container = switch orientation {
                case .h: "horizontal tiles container"
                case .v: "vertical tiles container"
                case nil: "tiles container"
            }
            throw CmdFail("Can't resize: the window isn't inside a \(container)")
        }
        let diff: CGFloat = switch units {
            case .set(let unit): CGFloat(unit) - node.getWeight(parent.orientation)
            case .add(let unit): CGFloat(unit)
            case .subtract(let unit): -CGFloat(unit)
        }

        guard let childDiff = diff.div(parent.children.count - 1) else {
            throw CmdFail("Can't resize: there are no other tiling windows \(parent.orientation == .h ? "to the left or right" : "above or below")")
        }
        for child in parent.children where child != node {
            child.setWeight(parent.orientation, child.getWeight(parent.orientation) - childDiff)
        }

        node.setWeight(parent.orientation, node.getWeight(parent.orientation) + diff)
    }
}

struct BalanceSizesCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var workspace: WorkspaceName? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var result = Self()
        while let option = try a.nextOption() {
            switch option {
                case "--workspace": result.workspace = try a.workspace(of: option)
                default: throw .unknownOption(option)
            }
        }
        try a.end()
        return result
    }

    func run(_ cx: CmdContext) throws(CmdFail) {
        balance(try cx.target(workspace: workspace).workspace.rootTilingContainer)
    }
}

private func balance(_ parent: TilingContainer) {
    for child in parent.children {
        switch parent.layout {
            case .tiles: child.setWeight(parent.orientation, 1)
            case .accordion: break // Do nothing
        }
        if let child = child as? TilingContainer {
            balance(child)
        }
    }
}

struct FlattenWorkspaceTreeCommand: nonisolated Command {
    static let resetsClosedWindowsCache = true
    var source: SourceWords = []
    var workspace: WorkspaceName? = nil

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var result = Self()
        while let option = try a.nextOption() {
            switch option {
                case "--workspace": result.workspace = try a.workspace(of: option)
                default: throw .unknownOption(option)
            }
        }
        try a.end()
        return result
    }

    func run(_ cx: CmdContext) throws(CmdFail) {
        let workspace = try cx.target(workspace: workspace).workspace
        let windows = workspace.rootTilingContainer.allLeafWindowsRecursive
        for window in windows {
            window.bind(to: workspace.rootTilingContainer, weight: 1)
        }
    }
}
