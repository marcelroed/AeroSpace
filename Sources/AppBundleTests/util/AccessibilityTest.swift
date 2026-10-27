@testable import AppBundle
import AppKit
import Common
import Testing

@Suite
struct AccessibilityTest {
    // RB-07: an app that returned an unexpected value used to crash AeroSpace
    @Test
    func testSizeAndPositionGettersReturnNilForUnexpectedValues() {
        var size = CGSize(width: 1, height: 2)
        var point = CGPoint(x: 3, y: 4)
        let sizeValue = unsafe AXValueCreate(.cgSize, &size).orDie()
        let pointValue = unsafe AXValueCreate(.cgPoint, &point).orDie()

        #expect(Ax.sizeAttr.getter(sizeValue) == size)
        #expect(Ax.topLeftCornerAttr.getter(pointValue) == point)

        // An AXValue of another type
        #expect(Ax.sizeAttr.getter(pointValue) == nil)
        #expect(Ax.topLeftCornerAttr.getter(sizeValue) == nil)

        // Not an AXValue
        #expect(Ax.sizeAttr.getter("100x200" as NSString) == nil)
        #expect(Ax.topLeftCornerAttr.getter(NSNumber(value: 1)) == nil)
    }

    // RB-45: values that aren't AX elements used to be force-cast to AXUIElement and passed to the AX API
    @Test
    func testAxElementGettersSkipValuesThatAreNotAxElements() {
        #expect(Ax.parentWindowRecursive.getter("not an AX element" as NSString) == nil)
        // Only documents the behavior: it passes without the type check too, because _AXUIElementGetWindow rejects a
        // value that isn't an AX element, so the value is dropped anyway. The assertion above is the regression check
        #expect(Ax.windowsAttr.getter(["not an AX element" as NSString, NSNumber(value: 1)] as NSArray)?.count == 0)
    }
}
