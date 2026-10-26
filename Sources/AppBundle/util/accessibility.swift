import AppKit
import Common
import PrivateApi

@MainActor
func waitForAccessibilityPermission_nonCancellable() async {
    let options = [axTrustedCheckOptionPrompt: true]
    while true {
        let status = TrayMenuModel.shared.axPermissionStatus == .waitingWithPrompt
            ? AXIsProcessTrustedWithOptions(options as CFDictionary)
            : AXIsProcessTrusted()
        if status {
            TrayMenuModel.shared.axPermissionStatus = .granted
            break
        }
        if TrayMenuModel.shared.axPermissionStatus == .waitingWithPrompt {
            resetAccessibility() // Because macOS doesn't reset it for us when the app signature changes...
        }
        TrayMenuModel.shared.axPermissionStatus = .waiting
        try? await Task.sleep(for: .seconds(1))
    }
}

private func resetAccessibility() {
    _ = try? Process.run(URL(filePath: "/usr/bin/tccutil"), arguments: ["reset", "Accessibility", aeroSpaceAppId])
}

protocol ReadableAttr: Sendable {
    associatedtype T
    var getter: @Sendable (AnyObject) -> T? { get }
    var key: String { get }
}

protocol WritableAttr: ReadableAttr, Sendable {
    var setter: @Sendable (T) -> CFTypeRef? { get }
}

// Attribute names: kAX*Attribute constants in ApplicationServices/HIServices/AXAttributeConstants.h
enum Ax {
    struct ReadableAttrImpl<T>: ReadableAttr {
        var key: String
        var getter: @Sendable (AnyObject) -> T?
    }

    struct WritableAttrImpl<T>: WritableAttr {
        var key: String
        var getter: @Sendable (AnyObject) -> T?
        var setter: @Sendable (T) -> CFTypeRef?
    }

    private static func readableString(_ key: String) -> ReadableAttrImpl<String> {
        ReadableAttrImpl(key: key, getter: { $0 as? String })
    }

    private static func readableBool(_ key: String) -> ReadableAttrImpl<Bool> {
        ReadableAttrImpl(key: key, getter: { $0 as? Bool })
    }

    private static func writableBool(_ key: String) -> WritableAttrImpl<Bool> {
        WritableAttrImpl(key: key, getter: { $0 as? Bool }, setter: { $0 as CFTypeRef })
    }

    private static func readableAxUiElementMock(_ key: String) -> ReadableAttrImpl<any AxUiElementMock> {
        ReadableAttrImpl(key: key, getter: castToAxUiElementMock)
    }

    static let parentWindowRecursive = ReadableAttrImpl<AXUIElement>(
        key: kAXWindowAttribute,
        getter: { ($0 as! AXUIElement) },
    )
    static let titleAttr = readableString(kAXTitleAttribute)
    static let roleAttr = readableString(kAXRoleAttribute)
    static let subroleAttr = readableString(kAXSubroleAttribute)
    static let identifierAttr = readableString(kAXIdentifierAttribute)
    static let enabledAttr = readableBool(kAXEnabledAttribute)
    static let enhancedUserInterfaceAttr = writableBool("AXEnhancedUserInterface")
    static let minimizedAttr = writableBool(kAXMinimizedAttribute)
    static let isFullscreenAttr = writableBool("AXFullScreen")
    static let isFocused = readableBool(kAXFocusedAttribute)
    static let isMainAttr = writableBool(kAXMainAttribute)
    static let sizeAttr = WritableAttrImpl<CGSize>(
        key: kAXSizeAttribute,
        getter: {
            // The app can return a value of any type. AXValueGetValue returns false for an AXValue of another type
            guard CFGetTypeID($0) == AXValueGetTypeID() else { return nil }
            var raw: CGSize = .zero
            return unsafe AXValueGetValue($0 as! AXValue, .cgSize, &raw) ? raw : nil
        },
        setter: {
            var size = $0
            return unsafe AXValueCreate(.cgSize, &size) as CFTypeRef
        },
    )
    static let topLeftCornerAttr = WritableAttrImpl<CGPoint>(
        key: kAXPositionAttribute,
        getter: {
            // The app can return a value of any type. AXValueGetValue returns false for an AXValue of another type
            guard CFGetTypeID($0) == AXValueGetTypeID() else { return nil }
            var raw: CGPoint = .zero
            return unsafe AXValueGetValue($0 as! AXValue, .cgPoint, &raw) ? raw : nil
        },
        setter: {
            var size = $0
            return unsafe AXValueCreate(.cgPoint, &size) as CFTypeRef
        },
    )
    /// Returns windows visible on all monitors
    /// If some windows are located on not active macOS Spaces then they won't be returned
    static let windowsAttr = ReadableAttrImpl<[WindowIdAndAxUiElement]>(
        key: kAXWindowsAttribute,
        getter: { ($0 as? NSArray)?.compactMap(axWindowOrNil) ?? [] },
    )
    static let focusedWindowAttr = ReadableAttrImpl<WindowIdAndAxUiElementMock>(
        key: kAXFocusedWindowAttribute,
        getter: windowOrNil,
    )
    static let closeButtonAttr = readableAxUiElementMock(kAXCloseButtonAttribute)
    // Note! fullscreen is not the same as "zoom" (green plus)
    static let fullscreenButtonAttr = readableAxUiElementMock(kAXFullScreenButtonAttribute)
    // green plus
    static let zoomButtonAttr = readableAxUiElementMock(kAXZoomButtonAttribute)
    static let minimizeButtonAttr = readableAxUiElementMock(kAXMinimizeButtonAttribute)
}

let kAXAeroSynthetic = "Aero.synthetic"

private func castToAxUiElementMock(_ a: AnyObject) -> any AxUiElementMock {
    isUnitTest ? axUiElementMockFromTestDump(a) : a as! AXUIElement
}

typealias WindowIdAndAxUiElement = (windowId: UInt32, ax: AXUIElement)
typealias WindowIdAndAxUiElementMock = (windowId: UInt32, ax: any AxUiElementMock)

private func windowOrNil(_ any: Any?) -> WindowIdAndAxUiElementMock? {
    guard let any else { return nil }
    let potentialWindow = castToAxUiElementMock(any as AnyObject)
    // Filter out non-window objects (e.g. Finder's desktop)
    return switch potentialWindow.containingWindowId() {
        case let windowId?: (windowId, potentialWindow)
        case nil: nil
    }
}

private func axWindowOrNil(_ any: Any) -> WindowIdAndAxUiElement? {
    let potentialWindow = any as AnyObject as! AXUIElement
    // Filter out non-window objects (e.g. Finder's desktop)
    return switch potentialWindow.containingWindowId() {
        case let windowId?: (windowId, potentialWindow)
        case nil: nil
    }
}

extension AXUIElement: AxUiElementMock {
    func get<Attr: ReadableAttr>(_ attr: Attr) -> Attr.T? {
        let state = signposter.beginInterval(#function, "attr: \(attr.key) axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
        defer { signposter.endInterval(#function, state) }
        var raw: AnyObject?
        return unsafe AXUIElementCopyAttributeValue(self, attr.key as CFString, &raw) == .success
            ? raw.flatMap(attr.getter)
            : nil
    }

    @discardableResult func set<Attr: WritableAttr>(_ attr: Attr, _ value: Attr.T) -> Bool {
        if serverArgs.isReadOnly { return false }
        let state = signposter.beginInterval(#function, "attr: \(attr.key) axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
        defer { signposter.endInterval(#function, state) }
        guard let value = attr.setter(value) else { return false }
        return AXUIElementSetAttributeValue(self, attr.key as CFString, value) == .success
    }

    func containingWindowId() -> CGWindowID? {
        let state = signposter.beginInterval(#function, "axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
        defer { signposter.endInterval(#function, state) }
        var cgWindowId = CGWindowID()
        return unsafe _AXUIElementGetWindow(self, &cgWindowId) == .success && cgWindowId != kCGNullWindowID
            ? cgWindowId
            : nil
    }
}

extension AXObserver {
    static func new(_ pid: pid_t, _ handler: AXObserverCallback) -> AXObserver? {
        var observer: AXObserver? = nil
        return unsafe AXObserverCreate(pid, handler, &observer) == .success ? observer : nil
    }
}
