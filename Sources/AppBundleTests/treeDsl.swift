@testable import AppBundle
import AppKit
import Common

// The tree DSL builds a workspace from a string, and renders a workspace back to the same string:
//
//     setUpTree("h_tiles(1 *2 v_accordion(3 4)) floating(5)")
//     expectEqual(describeTree(), "h_tiles(1 *2 v_accordion(3 4)) floating(5)")
//
// - A workspace is its root tiling container, followed by the containers of its other windows: `floating(...)`,
//   `macos_fullscreen(...)` (macOS native fullscreen) and `macos_hidden(...)` (windows of hidden apps).
//   `describeTree` prints the root, then the non-empty other containers in this order.
// - A tiling container is `h_tiles`, `v_tiles`, `h_accordion` or `v_accordion`. Its children are windows and tiling
//   containers.
// - A window is its id. `*` marks the focused window.
// - `:<weight>` after a window id or a container name is the weight of a tiling container's child, for example
//   `h_tiles(1:2 v_tiles:3(4 5))`. The default is 1. `describeTree(weights: true)` prints the weights.
// - `macos_minimized(...)` and `macos_popup(...)` put windows into the global containers of minimized and popup windows.
//   They aren't part of any workspace, so `describeTree` doesn't print them.
// - Several workspaces: `setUpTree(spec, workspace: "b")` and `describeTree("b")`. The tests have a single monitor, so
//   the DSL has no syntax for monitors.
//
// Binding a node makes it the most recent child of its parent, so the last child is the most recent one, except on the
// path to the focused window: focusing it makes it the most recent window. In the focused workspace, the focused window
// is its most recent window unless `*` marks another one.

/// Builds `spec` in the empty workspace `workspaceName` (default: the focused workspace) and focuses the window marked
/// with `*`. See the syntax above
@discardableResult
func setUpTree(_ spec: String, workspace workspaceName: String? = nil) -> Workspace {
    let workspace = workspaceName.map { Workspace.get(byName: $0) } ?? focus.workspace
    check(workspace.isEffectivelyEmpty, "Workspace '\(workspace.name)' isn't empty")
    var focused: [Window] = []
    for part in parseTreeSpec(spec) {
        let children = part.children.orDie("'\(part.name)': windows must be inside a container")
        let container: Container = switch part.name {
            case ContainerKind.floating.dslName: workspace.containerCreatingIfNeeded(.floating)
            case ContainerKind.macosFullscreen.dslName: workspace.containerCreatingIfNeeded(.macosFullscreen)
            case ContainerKind.macosHiddenApp.dslName: workspace.containerCreatingIfNeeded(.macosHiddenApp)
            case ContainerKind.macosMinimized.dslName: macosMinimizedWindowsContainer
            case ContainerKind.macosPopup.dslName: macosPopupWindowsContainer
            default: setUpRoot(of: workspace, part)
        }
        for child in children {
            check(container is TilingContainer || child.children == nil && child.weight == nil, "'\(part.name)' holds only windows without weights")
            build(child, in: container, focused: &focused)
        }
    }
    check(focused.count <= 1, "More than one focused window in '\(spec)'")
    if let window = focused.first {
        check(window.focusWindow())
    }
    return workspace
}

private func setUpRoot(of workspace: Workspace, _ spec: SpecNode) -> TilingContainer {
    check(spec.weight == nil, "The root container has no weight")
    let (layout, orientation) = tilingKind(spec.name)
    let root = workspace.rootTilingContainerCreatingIfNeeded()
    root.layout = layout
    root.changeOrientation(orientation)
    return root
}

/// Renders the workspace `workspaceName` (default: the focused workspace) in the tree DSL, see ``setUpTree``. A workspace
/// without a root container is rendered with the root that it would get, and doesn't get one
func describeTree(_ workspaceName: String? = nil, weights: Bool = false) -> String {
    let workspace = workspaceName.map { Workspace.get(byName: $0) } ?? focus.workspace
    let (layout, orientation) = workspace.rootLayout
    var parts = [workspace.existingRootTilingContainer.map { describeNode($0, weights: weights) } ?? "\(orientation)_\(layout.rawValue)()"]
    for kind: ContainerKind in [.floating, .macosFullscreen, .macosHiddenApp] {
        if let container = workspace.existingContainer(kind), !container.children.isEmpty {
            parts.append(describeNode(container))
        }
    }
    return parts.joined(separator: " ")
}

/// Renders a node in the tree DSL, see ``setUpTree``. A workspace is rendered as its children. `mru`: the children of every
/// node in MRU order, the most recent first, instead of their order. That shows the whole MRU state of the subtree
func describeNode(_ node: TreeNode, weights: Bool = false, mru: Bool = false) -> String {
    let focusedWindowId = focus.windowOrNil?.windowId
    func describe(_ node: TreeNode) -> String {
        let weight = switch node.parent {
            case let parent as TilingContainer where weights: ":\(node.getWeight(parent.orientation).dslDescription)"
            default: ""
        }
        let children = (mru ? node.mruChildren : node.children).map(describe).joined(separator: " ")
        return switch node {
            case let window as Window: "\(window.windowId == focusedWindowId ? "*" : "")\(window.windowId)\(weight)"
            case let container as TilingContainer: "\(container.orientation)_\(container.layout.rawValue)\(weight)(\(children))"
            case let container as Container: "\(container.kind.dslName)(\(children))"
            case is Workspace: children
            default: dieT("Unknown node \(node.prettyDescription)")
        }
    }
    return describe(node)
}

/// The test window with id `id`, bound or not
func testWindow(_ id: WindowId) -> TestWindow {
    TestApp.shared.windows.singleOrNil(where: { $0.windowId == id }).orDie("No test window with id \(id)") as? TestWindow ?? dieT()
}

func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> Rect {
    Rect(topLeftX: x, topLeftY: y, width: width, height: height)
}

/// A window id or a container name, with the children of the container (nil for a window)
private struct SpecNode {
    let name: String
    let isFocused: Bool
    let weight: CGFloat?
    let children: [SpecNode]?
}

private func parseTreeSpec(_ spec: String) -> [SpecNode] {
    var rest = Substring(spec)
    func parseList() -> [SpecNode] {
        var result: [SpecNode] = []
        while true {
            rest = rest.drop(while: \.isWhitespace)
            guard let first = rest.first, first != ")" else { return result }
            var token = rest.prefix { !$0.isWhitespace && $0 != "(" && $0 != ")" }
            rest = rest.dropFirst(token.count)
            let isFocused = token.first == "*"
            if isFocused { token = token.dropFirst() }
            let nameAndWeight = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let weight: Double? = nameAndWeight.count == 2 ? Double(nameAndWeight[1]).orDie("Weight in '\(token)' isn't a number") : nil
            var children: [SpecNode]? = nil
            if rest.first == "(" {
                rest = rest.dropFirst()
                children = parseList()
                check(rest.first == ")", "Missing ')' in '\(spec)'")
                rest = rest.dropFirst()
            }
            check(!isFocused || children == nil, "Only windows can be focused: '\(spec)'")
            result.append(SpecNode(name: String(nameAndWeight[0]), isFocused: isFocused, weight: weight.map { CGFloat($0) }, children: children))
        }
    }
    let result = parseList()
    check(rest.isEmpty, "Unexpected ')' in '\(spec)'")
    return result
}

private func build(_ node: SpecNode, in parent: Container, focused: inout [Window]) {
    if let children = node.children {
        let (layout, orientation) = tilingKind(node.name)
        let container = TilingContainer(parent: parent, weight: node.weight ?? 1, orientation, layout)
        for child in children {
            build(child, in: container, focused: &focused)
        }
    } else {
        let id = WindowId(raw: UInt32(node.name).orDie("'\(node.name)' isn't a window id"))
        let window = TestWindow.new(id: id, parent: parent, weight: node.weight ?? 1)
        if node.isFocused { focused.append(window) }
    }
}

private func tilingKind(_ name: String) -> (Layout, Orientation) {
    let parts = name.split(separator: "_", maxSplits: 1)
    let orientation: Orientation? = switch parts.first {
        case "h": .h
        case "v": .v
        default: nil
    }
    guard parts.count == 2, let orientation, let layout = Layout(rawValue: String(parts[1])) else {
        die("'\(name)' isn't a container: h_tiles, v_tiles, h_accordion, v_accordion, floating, macos_fullscreen, macos_hidden, macos_minimized or macos_popup")
    }
    return (layout, orientation)
}

extension CGFloat {
    /// `2` instead of `2.0`
    fileprivate var dslDescription: String {
        self == rounded() ? String(Int(self)) : description
    }
}

extension ContainerKind {
    /// The name of a container that isn't tiling in the tree DSL
    fileprivate var dslName: String {
        switch self {
            case .tiling: "tiling"
            case .floating: "floating"
            case .macosFullscreen: "macos_fullscreen"
            case .macosHiddenApp: "macos_hidden"
            case .macosMinimized: "macos_minimized"
            case .macosPopup: "macos_popup"
        }
    }
}
