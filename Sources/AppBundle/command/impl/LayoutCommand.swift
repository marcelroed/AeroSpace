import AppKit
import Common

struct LayoutCommand: Command {
    let args: LayoutCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        if args.forNextDetectedWindow {
            if let it = args.toggleBetween.val.singleOrNil() {
                global_layoutForNextDetectedWindow = it
                return .succ
            } else {
                return .fail(io.err(bugPrompt()))
            }
        }
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }

        let node: TilingContainer? // nil if the window is floating
        switch args.root ? nil : target.windowOrNil {
            case let window?:
                switch window.parent?.cases {
                    case .floatingWindowsContainer:
                        node = nil
                    case .tilingContainer(let it):
                        node = it
                    case .macosFullscreenWindowsContainer,
                         .macosHiddenAppsWindowsContainer,
                         .macosMinimizedWindowsContainer:
                        let msg = "Can't change layout for macOS minimized, fullscreen windows or windows or hidden apps. " +
                            "This behavior is subject to change"
                        return .fail(io.err(msg))
                    case nil, .workspace, .macosPopupWindowsContainer:
                        return .fail(io.err(bugPrompt()))
                }
            case nil:
                node = target.workspace.rootTilingContainer
        }

        let targetDescription = args.toggleBetween.val.first(where: { !node.matchesDescription($0) })
            ?? args.toggleBetween.val.first.orDie()
        if node.matchesDescription(targetDescription) {
            return .noop(io, failIfNoop: args.failIfNoop, "Already in the requested \(targetDescription.rawValue) mode. " +
                "Tip: use --fail-if-noop to exit with non-zero exit code")
        }
        switch targetDescription {
            case .h_accordion:
                return changeTilingLayout(io, targetLayout: .accordion, targetOrientation: .h, node: node)
            case .v_accordion:
                return changeTilingLayout(io, targetLayout: .accordion, targetOrientation: .v, node: node)
            case .h_tiles:
                return changeTilingLayout(io, targetLayout: .tiles, targetOrientation: .h, node: node)
            case .v_tiles:
                return changeTilingLayout(io, targetLayout: .tiles, targetOrientation: .v, node: node)
            case .accordion:
                return changeTilingLayout(io, targetLayout: .accordion, targetOrientation: nil, node: node)
            case .tiles:
                return changeTilingLayout(io, targetLayout: .tiles, targetOrientation: nil, node: node)
            case .horizontal:
                return changeTilingLayout(io, targetLayout: nil, targetOrientation: .h, node: node)
            case .vertical:
                return changeTilingLayout(io, targetLayout: nil, targetOrientation: .v, node: node)
            case .tiling:
                guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
                if node != nil { return .succ } // Nothing to do
                let workspace = window.nodeWorkspace // The floating container's workspace. Read it before the suspension point
                window.lastFloatingSize = (try? await window.getAxSize(.nonCancellable)) ?? window.lastFloatingSize
                guard let workspace else { return .fail(io.err(bugPrompt())) }
                do {
                    try await window.relayoutWindow(on: workspace, .nonCancellable, forceTile: true)
                } catch {
                    return .fail(io.err(bugPrompt()))
                }
                return .succ
            case .floating:
                guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
                let workspace = target.workspace
                window.bindAsFloatingWindow(to: workspace)
                if let size = window.lastFloatingSize { window.setAxFrame(nil, size) }
                return .succ
        }
    }
}

@MainActor var global_layoutForNextDetectedWindow: LayoutCmdArgs.LayoutDescription? = nil

@MainActor private func changeTilingLayout(
    _ io: CmdIo,
    targetLayout: Layout?,
    targetOrientation: Orientation?,
    node: TilingContainer?,
) -> BinaryExitCode {
    guard let parent = node else { return .fail(io.err("The window is non-tiling")) }
    let targetOrientation = targetOrientation ?? parent.orientation
    let targetLayout = targetLayout ?? parent.layout
    parent.layout = targetLayout
    parent.changeOrientation(targetOrientation)
    return .succ
}

extension TilingContainer? { // nil is a floating window
    @MainActor fileprivate func matchesDescription(_ layout: LayoutCmdArgs.LayoutDescription) -> Bool {
        return switch layout {
            case .accordion:   self?.layout == .accordion
            case .tiles:       self?.layout == .tiles
            case .horizontal:  self?.orientation == .h
            case .vertical:    self?.orientation == .v
            case .h_accordion: self.map { $0.layout == .accordion && $0.orientation == .h } == true
            case .v_accordion: self.map { $0.layout == .accordion && $0.orientation == .v } == true
            case .h_tiles:     self.map { $0.layout == .tiles && $0.orientation == .h } == true
            case .v_tiles:     self.map { $0.layout == .tiles && $0.orientation == .v } == true
            case .tiling:      self != nil
            case .floating:    self == nil
        }
    }
}
