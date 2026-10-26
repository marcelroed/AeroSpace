import AppKit
import Common

/// An AX element whose attributes can be read. Despite the name, it's not test-only: ``AXUIElement`` conforms in
/// production, and unit tests use elements parsed from JSON dumps (see ``axUiElementMockFromTestDump(_:)``)
protocol AxUiElementMock {
    func get<Attr: ReadableAttr>(_ attr: Attr) -> Attr.T?
    func containingWindowId() -> CGWindowID?
}

extension AxUiElementMock {
    var cast: AXUIElement { self as! AXUIElement }
}

/// In unit tests, AX elements come from JSON dumps: either dictionaries or "AXUIElement(AxWindowId=…" strings
func axUiElementMockFromTestDump(_ a: AnyObject) -> any AxUiElementMock {
    if let str = a as? String, let commaIndex = str.firstIndex(of: ",") {
        let windowId = UInt32.init(String(str.prefix(upTo: commaIndex)).removePrefix("AXUIElement(AxWindowId="))
        if let windowId {
            return axUiElementMockFromTestDump([
                "Aero.axWindowId": Json.int(windowId),
                kAXAeroSynthetic: Json.bool(true),
            ] as AnyObject)
        }
    }
    if let dict = a as? [String: Json] { // Convert from _SwiftDeferredNSDictionary<String, Json>
        return dict as? AxUiElementMock ?? dieT("Cannot cast \(type(of: a)) to AxUiElementMock")
    }
    die("Can't convert \(a) to AxUiElementMock")
}
