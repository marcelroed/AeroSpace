@testable import AppBundle
import Common
import Testing

/// ``World/withTemporaryTreeEdits(_:)`` puts back the fields of the nodes that it saved by hand. The test compares every
/// stored field of every node before and after, so a row fails for a field that its edit changes and that isn't restored
@Suite(.aeroSpaceGlobalState)
struct TemporaryTreeEditsTest {
    struct EditCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let edit: @MainActor @Sendable () -> Void

        nonisolated init(_ name: String, _ edit: @escaping @MainActor @Sendable () -> Void) {
            testDescription = name
            self.edit = edit
        }
    }

    @Test(arguments: [
        EditCase("moves within a parent and into another container") {
            testWindow(1).move(to: root("a"), at: 2, weight: .keep)
            testWindow(3).move(to: testWindow(4).parent.orDie(), at: 0, weight: .value(5))
        },
        EditCase("a floating window becomes tiling") { testWindow(6).move(to: root("a"), at: 0) },
        EditCase("wrap") { testWindow(2).wrap(.h, .accordion) },
        EditCase("wrap the root") { root("a").wrap(.v, .tiles) },
        EditCase("swap") { testWindow(1).swap(with: testWindow(5)) },
        EditCase("mark the most recent child") {
            testWindow(2).markAsMostRecentChild()
            testWindow(6).markAsMostRecentChild()
        },
        EditCase("create the root") { testWindow(11).move(to: Workspace.get(byName: "c").rootTilingContainerCreatingIfNeeded()) },
        EditCase("change the orientation and the layout") {
            root("a").changeOrientation(.v)
            root("a").layout = .accordion
        },
        EditCase("normalize: flatten and change the orientation") { Workspace.get(byName: "a").normalizeContainers() },
        EditCase("move nodes between the trees") {
            testWindow(4).parent.orDie().move(to: root("b"))
            testWindow(8).move(to: root("a"))
            testWindow(7).move(to: macosMinimizedWindowsContainer)
            testWindow(9).move(to: Workspace.get(byName: "new").rootTilingContainerCreatingIfNeeded())
        },
    ] as [EditCase])
    func temporaryEditsAreUndone(_ it: EditCase) {
        world.config.enableNormalizationFlattenContainers = true // The config's defaults
        world.config.enableNormalizationOppositeOrientationForNestedContainers = true
        setUpTree("h_tiles(1:2 v_tiles(2 3) v_tiles(h_tiles(4 5))) floating(6 7)", workspace: "a")
        setUpTree("v_tiles(8 9) macos_fullscreen(10) macos_minimized(12)", workspace: "b")
        setUpTree("floating(11)", workspace: "c")
        let roots: [TreeNode] = Workspace.all + [macosMinimizedWindowsContainer, macosPopupWindowsContainer]
        let before = fieldsOfEveryNode(roots)

        let edited = world.withTemporaryTreeEdits {
            it.edit()
            return fieldsOfEveryNode(roots) != before
        }

        #expect(edited, "The edit changes nothing")
        expectEqual(fieldsOfEveryNode(roots), before)
        #expect(Workspace.all.allSatisfy { roots.contains($0) || $0.children.isEmpty }, "A new workspace is left empty")
    }
}

private func root(_ workspaceName: String) -> TilingContainer {
    Workspace.get(byName: workspaceName).existingRootTilingContainer.orDie()
}

/// Every stored field of every node, depth first, one line per node. A node in a field (the parent, the children) is
/// its identity, so that a node replaced by an equal-looking one shows
private func fieldsOfEveryNode(_ roots: [TreeNode]) -> [String] {
    var result: [String] = []
    func visit(_ node: TreeNode) {
        var fields: [String] = [identity(node)]
        var mirror: Mirror? = Mirror(reflecting: node)
        while let current = mirror {
            for case let (name?, value) in current.children {
                let description: String = switch value {
                    case let node as TreeNode: identity(node)
                    case let nodes as [TreeNode]: "[\(nodes.map(identity).joined(separator: ", "))]"
                    default: "\(value)"
                }
                fields.append("\(name): \(description)")
            }
            mirror = current.superclassMirror
        }
        result.append(fields.joined(separator: ", "))
        node.children.forEach(visit)
    }
    roots.forEach(visit)
    return result
}

private func identity(_ node: TreeNode) -> String {
    "\(type(of: node))@\(String(UInt(bitPattern: ObjectIdentifier(node)), radix: 16))"
}
