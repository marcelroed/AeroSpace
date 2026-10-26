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

        assertEquals(Ax.sizeAttr.getter(sizeValue), size)
        assertEquals(Ax.topLeftCornerAttr.getter(pointValue), point)

        // An AXValue of another type
        assertNil(Ax.sizeAttr.getter(pointValue))
        assertNil(Ax.topLeftCornerAttr.getter(sizeValue))

        // Not an AXValue
        assertNil(Ax.sizeAttr.getter("100x200" as NSString))
        assertNil(Ax.topLeftCornerAttr.getter(NSNumber(value: 1)))
    }

    // RB-45: values that aren't AX elements used to be force-cast to AXUIElement and passed to the AX API
    @Test
    func testAxElementGettersSkipValuesThatAreNotAxElements() {
        assertNil(Ax.parentWindowRecursive.getter("not an AX element" as NSString))
        assertEquals(Ax.windowsAttr.getter(["not an AX element" as NSString, NSNumber(value: 1)] as NSArray)?.count, 0)
    }
}
