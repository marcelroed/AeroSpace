import AppKit
import Common
import PrivateApi

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

// The AX attributes are read and written on the AX app threads
nonisolated protocol ReadableAttr: Sendable {
    associatedtype T
    var getter: @Sendable (AnyObject) -> T? { get }
    var key: String { get }
}

nonisolated protocol WritableAttr: ReadableAttr, Sendable {
    var setter: @Sendable (T) -> CFTypeRef? { get }
}

// Attribute names: kAX*Attribute constants in ApplicationServices/HIServices/AXAttributeConstants.h
nonisolated enum Ax {
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

    /// An attribute whose value is an AXValue of the given type
    private static func writableAxValue<V: BitwiseCopyable & Sendable>(_ key: String, _ type: AXValueType, _ zero: V) -> WritableAttrImpl<V> {
        WritableAttrImpl(
            key: key,
            getter: {
                // The app can return a value of any type. AXValueGetValue returns false for an AXValue of another type
                guard CFGetTypeID($0) == AXValueGetTypeID() else { return nil }
                var raw = zero
                return unsafe AXValueGetValue($0 as! AXValue, type, &raw) ? raw : nil
            },
            setter: {
                var value = $0
                return unsafe AXValueCreate(type, &value) as CFTypeRef
            },
        )
    }

    static let parentWindowRecursive = ReadableAttrImpl<AXUIElement>(
        key: kAXWindowAttribute,
        getter: { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil },
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
    static let sizeAttr = writableAxValue(kAXSizeAttribute, .cgSize, CGSize.zero)
    static let topLeftCornerAttr = writableAxValue(kAXPositionAttribute, .cgPoint, CGPoint.zero)
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

nonisolated let kAXAeroSynthetic = "Aero.synthetic"

// `as! AXUIElement` doesn't check anything at runtime (it's a CoreFoundation type). Check the type ID instead
nonisolated private func castToAxUiElementMock(_ a: AnyObject) -> (any AxUiElementMock)? {
    if isUnitTest { return axUiElementMockFromTestDump(a) }
    return CFGetTypeID(a) == AXUIElementGetTypeID() ? (a as! AXUIElement) : nil
}

typealias WindowIdAndAxUiElement = (windowId: UInt32, ax: AXUIElement)
typealias WindowIdAndAxUiElementMock = (windowId: UInt32, ax: any AxUiElementMock)

nonisolated private func windowOrNil(_ obj: AnyObject) -> WindowIdAndAxUiElementMock? {
    guard let potentialWindow = castToAxUiElementMock(obj) else { return nil }
    // Filter out non-window objects (e.g. Finder's desktop)
    return potentialWindow.containingWindowId().map { ($0, potentialWindow) }
}

nonisolated private func axWindowOrNil(_ any: Any) -> WindowIdAndAxUiElement? {
    let object = any as AnyObject
    guard CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
    let potentialWindow = object as! AXUIElement
    // Filter out non-window objects (e.g. Finder's desktop)
    return potentialWindow.containingWindowId().map { ($0, potentialWindow) }
}

nonisolated extension AXUIElement: AxUiElementMock {
    func get<Attr: ReadableAttr>(_ attr: Attr) -> Attr.T? {
        let state = signposter.beginInterval(#function, "attr: \(attr.key) axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug ?? "nil")")
        defer { signposter.endInterval(#function, state) }
        var raw: AnyObject?
        return unsafe AXUIElementCopyAttributeValue(self, attr.key as CFString, &raw) == .success
            ? raw.flatMap(attr.getter)
            : nil
    }

    @discardableResult func set<Attr: WritableAttr>(_ attr: Attr, _ value: Attr.T) -> Bool {
        if serverArgs.isReadOnly { return false }
        let state = signposter.beginInterval(#function, "attr: \(attr.key) axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug ?? "nil")")
        defer { signposter.endInterval(#function, state) }
        guard let value = attr.setter(value) else { return false }
        return AXUIElementSetAttributeValue(self, attr.key as CFString, value) == .success
    }

    func containingWindowId() -> CGWindowID? {
        let state = signposter.beginInterval(#function, "axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug ?? "nil")")
        defer { signposter.endInterval(#function, state) }
        var cgWindowId = CGWindowID()
        return unsafe _AXUIElementGetWindow(self, &cgWindowId) == .success && cgWindowId != kCGNullWindowID
            ? cgWindowId
            : nil
    }
}
