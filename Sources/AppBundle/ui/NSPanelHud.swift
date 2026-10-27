import AppKit

open class NSPanelHud: NSPanel {
    init() {
        checkIsAeroSpaceApp("A panel")
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .hudWindow, .utilityWindow],
            backing: .buffered,
            defer: false,
        )
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.isMovableByWindowBackground = false
        self.alphaValue = 1
        self.hasShadow = true
        self.backgroundColor = .clear
    }

    /// A frame of the given size, 20pt away from the right edge of the main monitor
    func rightEdgeFrame(size: CGSize, y: CGFloat) -> NSRect {
        NSRect(x: world.monitors.main.width - size.width - 20, y: y, width: size.width, height: size.height)
    }
}
