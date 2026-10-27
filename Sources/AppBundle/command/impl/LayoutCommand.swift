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
            global_layoutForNextDetectedWindow = it
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

var global_layoutForNextDetectedWindow: LayoutCommand.LayoutDescription? = nil

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
