@testable import AppBundle
import AppKit
import Common
import Testing

/// Pins how `debug-windows` writes AX values. AxUiElementWindowTypeTest reads the committed dumps back
@Suite
struct AxDumpJsonTest {
    /// AX numbers and booleans are CF objects, and all of them convert to Int. So the dump shows booleans as 0/1
    @Test
    func testDumpRendersAxBooleansAsInts() {
        func pretty(_ raw: AnyObject?) -> OrderedJson { prettyValue(raw as Any?, recursionDepth: 1) }
        expectEqual(pretty(kCFBooleanTrue), .int(1))
        expectEqual(pretty(kCFBooleanFalse), .int(0))
        expectEqual(pretty(NSNumber(value: true)), .int(1))
        expectEqual(pretty(NSNumber(value: UInt32.max)), .int(Int64(UInt32.max)))
        expectEqual(pretty(NSArray(array: [kCFBooleanTrue.orDie(), NSNumber(value: 7)])), .array([.int(1), .int(7)]))
        expectEqual(pretty(nil), .null)
    }

    /// The committed dumps have these names, and AxUiElementWindowTypeTest reads them back
    @Test
    func testActivationPolicyNames() {
        let policies: [NSApplication.ActivationPolicy] = [.regular, .accessory, .prohibited]
        expectEqual(policies.map(\.prettyDescription), ["regular", "accessory", "prohibited"])
    }
}
