import Common

enum TreeNodeCases {
    case window(Window)
    case tilingContainer(TilingContainer)
    case workspace(Workspace)
    case macosMinimizedWindowsContainer(MacosMinimizedWindowsContainer)
    case macosHiddenAppsWindowsContainer(MacosHiddenAppsWindowsContainer)
    case macosFullscreenWindowsContainer(MacosFullscreenWindowsContainer)
    case macosPopupWindowsContainer(MacosPopupWindowsContainer)
    case floatingWindowsContainer(FloatingWindowsContainer)
}

enum NonLeafTreeNodeCases {
    case tilingContainer(TilingContainer)
    case workspace(Workspace)
    case macosMinimizedWindowsContainer(MacosMinimizedWindowsContainer)
    case macosHiddenAppsWindowsContainer(MacosHiddenAppsWindowsContainer)
    case macosFullscreenWindowsContainer(MacosFullscreenWindowsContainer)
    case macosPopupWindowsContainer(MacosPopupWindowsContainer)
    case floatingWindowsContainer(FloatingWindowsContainer)
}

enum TilingTreeNodeCases {
    case window(Window)
    case tilingContainer(TilingContainer)
}

enum NonLeafTreeNodeKind: Equatable {
    case tilingContainer
    case workspace
    case macosMinimizedWindowsContainer
    case macosHiddenAppsWindowsContainer
    case macosFullscreenWindowsContainer
    case macosPopupWindowsContainer
    case floatingWindowsContainer
}

protocol NonLeafTreeNodeObject: TreeNode {}

extension TreeNode {
    var nodeCases: TreeNodeCases {
        switch self {
            case let window as Window: .window(window)
            case let workspace as Workspace: .workspace(workspace)
            case let tilingContainer as TilingContainer: .tilingContainer(tilingContainer)
            case let container as MacosHiddenAppsWindowsContainer: .macosHiddenAppsWindowsContainer(container)
            case let container as MacosMinimizedWindowsContainer: .macosMinimizedWindowsContainer(container)
            case let container as MacosFullscreenWindowsContainer: .macosFullscreenWindowsContainer(container)
            case let container as MacosPopupWindowsContainer: .macosPopupWindowsContainer(container)
            case let container as FloatingWindowsContainer: .floatingWindowsContainer(container)
            default: die("Unknown tree")
        }
    }

    func tilingTreeNodeCasesOrDie() -> TilingTreeNodeCases {
        switch self {
            case let window as Window: .window(window)
            case let tilingContainer as TilingContainer: .tilingContainer(tilingContainer)
            default: illegalChildParentRelation(child: self, parent: parent)
        }
    }
}

extension NonLeafTreeNodeObject {
    var cases: NonLeafTreeNodeCases {
        switch nodeCases {
            case .window: die("Windows are leaf nodes. They can't have children")
            case .workspace(let workspace): .workspace(workspace)
            case .tilingContainer(let tilingContainer): .tilingContainer(tilingContainer)
            case .macosMinimizedWindowsContainer(let container): .macosMinimizedWindowsContainer(container)
            case .macosHiddenAppsWindowsContainer(let container): .macosHiddenAppsWindowsContainer(container)
            case .macosFullscreenWindowsContainer(let container): .macosFullscreenWindowsContainer(container)
            case .macosPopupWindowsContainer(let container): .macosPopupWindowsContainer(container)
            case .floatingWindowsContainer(let container): .floatingWindowsContainer(container)
        }
    }

    var kind: NonLeafTreeNodeKind {
        switch cases {
            case .tilingContainer: .tilingContainer
            case .floatingWindowsContainer: .floatingWindowsContainer
            case .workspace: .workspace
            case .macosMinimizedWindowsContainer: .macosMinimizedWindowsContainer
            case .macosFullscreenWindowsContainer: .macosFullscreenWindowsContainer
            case .macosHiddenAppsWindowsContainer: .macosHiddenAppsWindowsContainer
            case .macosPopupWindowsContainer: .macosPopupWindowsContainer
        }
    }
}

enum ChildParentRelation: Equatable {
    case floatingWindow
    case macosNativeFullscreenWindow
    case macosNativeHiddenAppWindow
    case macosNativeMinimizedWindow
    case macosPopupWindow
    case tiling(parent: TilingContainer) // todo consider splitting it on 'tiles' and 'accordion'
    case rootTilingContainer

    case shimContainerRelation
}

/// The legal edges of the tree. Any other child-parent pair is illegal
func getChildParentRelation(child: TreeNode, parent: NonLeafTreeNodeObject) -> ChildParentRelation {
    switch (child.nodeCases, parent.cases) {
        case (.window, .tilingContainer(let container)), (.tilingContainer, .tilingContainer(let container)): .tiling(parent: container)
        case (.tilingContainer, .workspace): .rootTilingContainer
        case (.floatingWindowsContainer, .workspace),
             (.macosFullscreenWindowsContainer, .workspace),
             (.macosHiddenAppsWindowsContainer, .workspace): .shimContainerRelation
        case (.window, .floatingWindowsContainer): .floatingWindow
        case (.window, .macosFullscreenWindowsContainer): .macosNativeFullscreenWindow
        case (.window, .macosHiddenAppsWindowsContainer): .macosNativeHiddenAppWindow
        case (.window, .macosMinimizedWindowsContainer): .macosNativeMinimizedWindow
        case (.window, .macosPopupWindowsContainer): .macosPopupWindow
        default: illegalChildParentRelation(child: child, parent: parent)
    }
}

func illegalChildParentRelation(
    child: TreeNode,
    parent: NonLeafTreeNodeObject?,
    file: StaticString = #fileID,
    line: Int = #line,
    column: Int = #column,
    function: String = #function,
) -> Never {
    let msg = "Illegal child-parent relation. Child: \(child.prettyDescription), Parent: \((parent ?? child.parent)?.prettyDescription ?? "nil")"
    die(msg, file: file, line: line, column: column, function: function)
}
