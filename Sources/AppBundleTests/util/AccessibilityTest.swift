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
}
