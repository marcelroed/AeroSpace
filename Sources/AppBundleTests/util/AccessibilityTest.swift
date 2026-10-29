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

        expectEqual(Ax.sizeAttr.getter(sizeValue), size)
        expectEqual(Ax.topLeftCornerAttr.getter(pointValue), point)

        // An AXValue of another type
        expectEqual(Ax.sizeAttr.getter(pointValue), nil)
        expectEqual(Ax.topLeftCornerAttr.getter(sizeValue), nil)

        // Not an AXValue
        expectEqual(Ax.sizeAttr.getter("100x200" as NSString), nil)
        expectEqual(Ax.topLeftCornerAttr.getter(NSNumber(value: 1)), nil)
    }

    // RB-45: values that aren't AX elements used to be force-cast to AXUIElement and passed to the AX API
    @Test
    func testAxElementGettersSkipValuesThatAreNotAxElements() {
        expectEqual(Ax.parentWindowRecursive.getter("not an AX element" as NSString), nil)
    }
}
