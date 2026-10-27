import AppKit
import Common

open class Window: TreeNode, Hashable {
    nonisolated let windowId: UInt32
    let app: any AbstractApp
    var lastFloatingSize: CGSize?
    var isFullscreen: Bool = false
    var noOuterGapsInFullscreen: Bool = false
    var layoutReason: LayoutReason = .standard

    init(id: UInt32, _ app: any AbstractApp, lastFloatingSize: CGSize?, parent: Container, weight: CGFloat?, index: Int?) {
        self.windowId = id
        self.app = app
        self.lastFloatingSize = lastFloatingSize
        super.init(parent: parent, weight: weight, index: index)
    }

    static func get(byId windowId: UInt32) -> Window? { // todo make non optional
        isUnitTest
            ? Workspace.all.flatMap { $0.allLeafWindowsRecursive }.first(where: { $0.windowId == windowId })
            : MacWindow.allWindowsMap[windowId]
    }

    func closeAxWindow() { die("Not implemented") }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(windowId)
    }

    func getAxSize(_ cm: CancellationMode) async throws -> CGSize? { die("Not implemented") }
    func getTitle(_ cm: CancellationMode) async throws -> String { die("Not implemented") }
    func isMacosFullscreen(_ cm: CancellationMode) async throws -> Bool { false }
    func isMacosMinimized(_ cm: CancellationMode) async throws -> Bool { false } // todo replace with enum MacOsWindowNativeState { normal, fullscreen, invisible }
    /// isMinimized is false if isFullscreen
    func getMacosFullscreenAndMinimized(_ cm: CancellationMode) async throws -> (isFullscreen: Bool, isMinimized: Bool) {
        if try await isMacosFullscreen(cm) { return (true, false) }
        return (false, try await isMacosMinimized(cm))
    }
    var isHiddenInCorner: Bool { die("Not implemented") }
    func nativeFocus() { die("Not implemented") }
    func getAxRect(_ cm: CancellationMode) async throws -> Rect? { die("Not implemented") }
    func getCenter(_ cm: CancellationMode) async throws -> CGPoint? { try await getAxRect(cm)?.center }

    func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) { die("Not implemented") }
}

enum LayoutReason: Equatable {
    case standard
    /// Reason for the cur temp layout is macOS native fullscreen, minimize, or hide
    case macos(prevParentKind: ContainerKind)
}

/// A window's parent, typed. The parent of a window is always a container
enum WindowPlacement: Equatable {
    case tiling(TilingContainer)
    case floating, macosFullscreen, macosHiddenApp, macosMinimized, macosPopup
}

extension Window {
    /// nil while the window is unbound
    var placement: WindowPlacement? {
        guard let parent = parent as? Container else { return nil }
        return switch parent.kind {
            case .tiling: .tiling(parent as? TilingContainer ?? dieT("A tiling container must be a TilingContainer"))
            case .floating: .floating
            case .macosFullscreen: .macosFullscreen
            case .macosHiddenApp: .macosHiddenApp
            case .macosMinimized: .macosMinimized
            case .macosPopup: .macosPopup
        }
    }

    var isFloating: Bool { (parent as? Container)?.kind == .floating } // todo drop. It will be a source of bugs when sticky is introduced

    func asMacWindow() -> MacWindow { self as! MacWindow }
}
