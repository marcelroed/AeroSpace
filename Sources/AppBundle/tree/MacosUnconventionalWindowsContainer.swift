import Common

final class MacosFullscreenWindowsContainer: TreeNode, NonLeafTreeNodeObject {
    init(parent: Workspace) {
        super.init(parent: parent)
    }
}

/// The container for macOS windows of hidden apps
final class MacosHiddenAppsWindowsContainer: TreeNode, NonLeafTreeNodeObject {
    init(parent: Workspace) {
        super.init(parent: parent)
    }
}

let macosMinimizedWindowsContainer = MacosMinimizedWindowsContainer()
final class MacosMinimizedWindowsContainer: TreeNode, NonLeafTreeNodeObject {
    override fileprivate init() {
        super.init()
    }
}

let macosPopupWindowsContainer = MacosPopupWindowsContainer()
/// The container for macOS objects that are windows from AX perspective but from human perspective they are not even
/// dialogs. E.g. Sonoma (macOS 14) keyboard layout switch
final class MacosPopupWindowsContainer: TreeNode, NonLeafTreeNodeObject {
    override fileprivate init() {
        super.init()
    }
}
