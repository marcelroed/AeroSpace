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

        let subject: LayoutSubject
        switch args.root ? nil : target.windowOrNil {
            case let window?:
                switch window.parent?.cases {
                    case .floatingWindowsContainer:
                        subject = .floatingWindow(window)
                    case .tilingContainer(let it):
                        subject = .tilingContainer(it)
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
                subject = .tilingContainer(target.workspace.rootTilingContainer)
        }

        let targetDescription = args.toggleBetween.val.first(where: { !subject.matches($0) })
            ?? args.toggleBetween.val.first.orDie()
        if subject.matches(targetDescription) {
            return .noop(io, failIfNoop: args.failIfNoop, "Already in the requested \(targetDescription.rawValue) mode. " +
                "Tip: use --fail-if-noop to exit with non-zero code")
        }
        switch targetDescription {
            case .h_accordion, .v_accordion, .h_tiles, .v_tiles, .accordion, .tiles, .horizontal, .vertical:
                guard case .tilingContainer(let parent) = subject else { return .fail(io.err("The window is non-tiling")) }
                parent.layout = targetDescription.tilingLayout ?? parent.layout
                parent.changeOrientation(targetDescription.tilingOrientation ?? parent.orientation)
                return .succ
            case .tiling:
                guard case .floatingWindow(let window) = subject else { return .succ } // Already tiling
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

var global_layoutForNextDetectedWindow: LayoutCmdArgs.LayoutDescription? = nil

/// What the layout command changes
private enum LayoutSubject {
    case tilingContainer(TilingContainer) // The window's tiling parent, or the workspace's root container
    case floatingWindow(Window)

    func matches(_ description: LayoutCmdArgs.LayoutDescription) -> Bool {
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

extension LayoutCmdArgs.LayoutDescription {
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
