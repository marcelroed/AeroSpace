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

/// In unit tests, AX elements come from JSON dumps: either dictionaries or "AXUIElement(AxWindowId=…" strings.
/// nil for any other value (a malformed dump), so that the test of that dump fails instead of the whole test run
func axUiElementMockFromTestDump(_ a: AnyObject) -> (any AxUiElementMock)? {
    if let str = a as? String, let commaIndex = str.firstIndex(of: ",") {
        let windowId = UInt32.init(String(str.prefix(upTo: commaIndex)).removePrefix("AXUIElement(AxWindowId="))
        if let windowId {
            let dict: OrderedJson.JsonDict = ["Aero.axWindowId": .int(windowId), kAXAeroSynthetic: .bool(true)]
            return axUiElementMockFromTestDump(dict as AnyObject)
        }
    }
    if let dict = a as? OrderedJson.JsonDict { // Unbox from __SwiftValue
        return dict as? AxUiElementMock ?? dieT("Cannot cast \(type(of: a)) to AxUiElementMock")
    }
    return nil
}
