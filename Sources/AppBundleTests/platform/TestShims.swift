@testable import AppBundle
import AppKit
import Common

/// Tests write window ids as literals
extension WindowId: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: UInt32) { self.init(raw: value) }
}

/// The platform of the current test, see ``setUpWorkspacesForTests()``
var fake: FakePlatform { world.platform as? FakePlatform ?? dieT("The test didn't call setUpWorkspacesForTests()") }

/// Today's test call sites: a window of ``testApp`` that ``fake`` knows
enum TestWindow {
    @discardableResult
    static func new(id: WindowId, parent: Container, weight: CGFloat = 1, rect: Rect? = nil) -> Window {
        fake.windows[id] = FakeWindow(app: testApp, rect: rect, title: "TestWindow(\(id))")
        return Window(id: id, testApp, parent: parent, weight: weight, index: nil)
    }
}

extension Window {
    /// What AX reports as the window's frame
    var rect: Rect? {
        get { fake.windows[windowId]?.rect }
        set { fake.windows[windowId]?.rect = newValue }
    }

    /// The frame writes, in order
    var setAxFrameHistory: [AxFrame] { fake.frames(of: windowId) }

    /// AxApp's, see ``PlacementState/lastFloatingSize``
    var lastFloatingSize: CGSize? { fake.windows[windowId]?.placement.lastFloatingSize }

    var isMacosFullscreenForTest: Bool {
        get { fake.windows[windowId]?.isFullscreen ?? false }
        set { fake.windows[windowId]?.isFullscreen = newValue }
    }
}
