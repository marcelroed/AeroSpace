import AppKit

/// An AX element whose attributes can be read. Despite the name, it's not test-only: ``AXUIElement`` conforms in
/// production, and unit tests use elements parsed from JSON dumps
nonisolated protocol AxUiElementMock {
    func get<Attr: ReadableAttr>(_ attr: Attr) -> Attr.T?
    func containingWindowId() -> CGWindowID?
}

nonisolated extension AxUiElementMock {
    var cast: AXUIElement { self as! AXUIElement }
}
