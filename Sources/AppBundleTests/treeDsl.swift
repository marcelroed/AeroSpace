@testable import AppBundle
import AppKit
import Common

// The tree DSL builds a workspace from a string, and renders a workspace back to the same string:
//
//     setUpTree("h_tiles(1 *2 v_accordion(3 4)) floating(5)")
//     #expect(describeTree() == "h_tiles(1 *2 v_accordion(3 4)) floating(5)")
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
@MainActor
@discardableResult
func setUpTree(_ spec: String, workspace workspaceName: String? = nil) -> Workspace {
    let workspace = workspaceName.map { Workspace.get(byName: $0) } ?? focus.workspace
    check(workspace.isEffectivelyEmpty, "Workspace '\(workspace.name)' isn't empty")
    var focused: [Window] = []
    for part in parseTreeSpec(spec) {
        let children = part.children.orDie("'\(part.name)': windows must be inside a container")
        let container: NonLeafTreeNodeObject = switch part.name {
            case "floating": workspace.floatingWindowsContainer
            case "macos_fullscreen": workspace.macOsNativeFullscreenWindowsContainer
            case "macos_hidden": workspace.macOsNativeHiddenAppsWindowsContainer
            case "macos_minimized": macosMinimizedWindowsContainer
            case "macos_popup": macosPopupWindowsContainer
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

@MainActor
private func setUpRoot(of workspace: Workspace, _ spec: SpecNode) -> TilingContainer {
    check(spec.weight == nil, "The root container has no weight")
    let (layout, orientation) = tilingKind(spec.name)
    let root = workspace.rootTilingContainer
    root.layout = layout
    root.changeOrientation(orientation)
    return root
}

/// Renders the workspace `workspaceName` (default: the focused workspace) in the tree DSL, see ``setUpTree``
@MainActor
func describeTree(_ workspaceName: String? = nil, weights: Bool = false) -> String {
    let workspace = workspaceName.map { Workspace.get(byName: $0) } ?? focus.workspace
    let focusedWindowId = focus.windowOrNil?.windowId
    func describe(_ node: TreeNode) -> String {
        let weight = switch node.parent {
            case let parent as TilingContainer where weights: ":" + node.getWeight(parent.orientation).dslDescription
            default: ""
        }
        return switch node.nodeCases {
            case .window(let window): (window.windowId == focusedWindowId ? "*" : "") + String(window.windowId) + weight
            case .tilingContainer(let container): "\(container.orientation)_\(container.layout.rawValue)" + weight + describeChildren(container)
            default: dieT("\(node.prettyDescription) can't be a child of a tiling container")
        }
    }
    func describeChildren(_ node: TreeNode) -> String {
        "(" + node.children.map(describe).joined(separator: " ") + ")"
    }
    var parts = [describe(workspace.rootTilingContainer)]
    for (name, kind): (String, NonLeafTreeNodeKind) in [
        ("floating", .floatingWindowsContainer),
        ("macos_fullscreen", .macosFullscreenWindowsContainer),
        ("macos_hidden", .macosHiddenAppsWindowsContainer),
    ] {
        let container = workspace.children.first { ($0 as? NonLeafTreeNodeObject)?.kind == kind }
        if let container, !container.children.isEmpty {
            parts.append(name + describeChildren(container))
        }
    }
    return parts.joined(separator: " ")
}

/// The test window with id `id`, bound or not
@MainActor
func testWindow(_ id: UInt32) -> TestWindow {
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
            let weight = nameAndWeight.count == 2 ? Double(nameAndWeight[1]).orDie("Weight in '\(token)' isn't a number") : nil
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

@MainActor
private func build(_ node: SpecNode, in parent: NonLeafTreeNodeObject, focused: inout [Window]) {
    if let children = node.children {
        let (layout, orientation) = tilingKind(node.name)
        let container = TilingContainer(parent: parent, adaptiveWeight: node.weight ?? 1, orientation, layout, index: INDEX_BIND_LAST)
        for child in children {
            build(child, in: container, focused: &focused)
        }
    } else {
        let id = UInt32(node.name).orDie("'\(node.name)' isn't a window id")
        let window = TestWindow.new(id: id, parent: parent, adaptiveWeight: node.weight ?? 1)
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
