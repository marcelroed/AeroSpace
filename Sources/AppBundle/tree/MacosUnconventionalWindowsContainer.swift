import Common

final class MacosFullscreenWindowsContainer: TreeNode, NonLeafTreeNodeObject {
    init(parent: Workspace) {
        super.init(parent: parent, adaptiveWeight: 1, index: INDEX_BIND_LAST)
    }
}

/// The container for macOS windows of hidden apps
final class MacosHiddenAppsWindowsContainer: TreeNode, NonLeafTreeNodeObject {
    init(parent: Workspace) {
        super.init(parent: parent, adaptiveWeight: 1, index: INDEX_BIND_LAST)
    }
}

let macosMinimizedWindowsContainer = MacosMinimizedWindowsContainer()
final class MacosMinimizedWindowsContainer: TreeNode, NonLeafTreeNodeObject {
    fileprivate init() {
        super.init(unboundRootWithAdaptiveWeight: 1)
    }
}

let macosPopupWindowsContainer = MacosPopupWindowsContainer()
/// The container for macOS objects that are windows from AX perspective but from human perspective they are not even
/// dialogs. E.g. Sonoma (macOS 14) keyboard layout switch
final class MacosPopupWindowsContainer: TreeNode, NonLeafTreeNodeObject {
    fileprivate init() {
        super.init(unboundRootWithAdaptiveWeight: 1)
    }
}
