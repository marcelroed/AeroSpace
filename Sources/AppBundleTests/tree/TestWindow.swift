@testable import AppBundle
import AppKit

final class TestWindow: Window, CustomStringConvertible {
    /// What AX reports as the window's frame
    var rect: Rect?
    var isMacosFullscreenForTest = false

    private init(_ id: UInt32, _ parent: Container, _ weight: CGFloat, _ rect: Rect?) {
        self.rect = rect
        super.init(id: id, TestApp.shared, lastFloatingSize: nil, parent: parent, weight: weight, index: nil)
    }

    @discardableResult
    static func new(id: UInt32, parent: Container, weight: CGFloat = 1, rect: Rect? = nil) -> TestWindow {
        let wi = TestWindow(id, parent, weight, rect)
        TestApp.shared._windows.append(wi)
        return wi
    }

    nonisolated var description: String { "TestWindow(\(windowId))" }

    override func nativeFocus() {
        appForTests = TestApp.shared
        TestApp.shared.focusedWindow = self
    }

    override func closeAxWindow() {
        destroy()
    }

    override func getTitle(_ cm: CancellationMode) async throws -> String { description }

    override func getAxRect(_ cm: CancellationMode) async throws -> Rect? { // todo change to not Optional
        rect
    }

    override func getAxSize(_ cm: CancellationMode) async throws -> CGSize? {
        rect.map { CGSize(width: $0.width, height: $0.height) }
    }

    override func isMacosFullscreen(_ cm: CancellationMode) async throws -> Bool { isMacosFullscreenForTest }

    private(set) var setAxFrameHistory: [AxFrame] = []
    override func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) {
        setAxFrameHistory.append(AxFrame(topLeft: topLeft, size: size))
    }
}

// periphery:ignore - false positive unused warning. The properties are read by the synthesized Equatable
struct AxFrame: Equatable {
    let topLeft: CGPoint?
    let size: CGSize?
}
