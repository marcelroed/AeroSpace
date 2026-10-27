@testable import AppBundle
import AppKit
import Common
import Testing

/// Pins the JSON that `debug-windows` prints, and how unit tests read the committed `axDumps` back
@Suite
struct AxDumpJsonTest {
    /// Encoded the same way as in `dumpWindowDebugInfo`
    @Test
    func testEncode() {
        var result: OrderedJson.JsonDict = [:]
        result["Aero.AXApp"] = .dict(["AXRole": .string("AXApplication"), "AXEnabled": .int(1), "AXEmpty": .dict([:])])
        result["Aero.on-window-detected"] = .array([.dict(["commands": .string("layout floating")]), .array([])])
        result["Aero.workspace"] = .null
        result["Aero.AxUiElementWindowType_isDialogHeuristic"] = .bool(false)
        result["Aero.axWindowId"] = .int(42)
        result["Aero.App.nsApp.appBundlePath"] = .string("file:///Applications/Foo%20Bar.app/ \"é\" 🙂")
        expectEqual(
            JSONEncoder.aeroSpaceDefault.encodeToString(OrderedJson.dict(result)),
            #"""
            {
              "Aero.AXApp" : {
                "AXEmpty" : {

                },
                "AXEnabled" : 1,
                "AXRole" : "AXApplication"
              },
              "Aero.App.nsApp.appBundlePath" : "file:///Applications/Foo%20Bar.app/ \"é\" 🙂",
              "Aero.AxUiElementWindowType_isDialogHeuristic" : false,
              "Aero.axWindowId" : 42,
              "Aero.on-window-detected" : [
                {
                  "commands" : "layout floating"
                },
                [

                ]
              ],
              "Aero.workspace" : null
            }
            """#,
        )
    }

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

    /// JSON booleans are NSNumbers too, so the test dump reader reads them as ints, the same way the dump wrote them
    @Test
    func testReadTestDump() throws {
        let raw = try JSONSerialization.jsonObject(
            with: Data(
                #"""
                {
                    "AXEnabled": true,
                    "AXFocused": 0,
                    "AXTitle": "a/b",
                    "AXIdentifier": null,
                    "AXSections": [false, {"k": "v"}],
                    "AXCloseButton": {"AXRole": "AXButton", "AXEnabled": 1},
                    "AXFocusedWindow": "AXUIElement(AxWindowId=7, title=\"t\", role=\"AXWindow\", subrole=nil)",
                    "Aero.axWindowId": 5,
                }
                """#.utf8,
            ),
            options: [.json5Allowed],
        )
        let dump = try #require(OrderedJson.newOrNilRecursive(raw)?.asDictOrNil)
        expectEqual(dump["AXEnabled"], .int(1))
        expectEqual(dump["AXFocused"], .int(0))
        expectEqual(dump["AXTitle"], .string("a/b"))
        expectEqual(dump["AXIdentifier"], .null)
        expectEqual(dump["AXSections"], .array([.int(0), .dict(["k": .string("v")])]))

        expectEqual(dump.get(Ax.enabledAttr), true)
        expectEqual(dump.get(Ax.isFocused), false)
        expectEqual(dump.get(Ax.titleAttr), "a/b")
        expectEqual(dump.get(Ax.identifierAttr), nil)
        expectEqual(dump.get(Ax.subroleAttr), nil) // Missing keys are nil, unless the dump is synthetic
        expectEqual(dump.containingWindowId(), 5)
        expectEqual(dump.get(Ax.closeButtonAttr)?.get(Ax.roleAttr), "AXButton")
        expectEqual(dump.get(Ax.closeButtonAttr)?.get(Ax.enabledAttr), true)
        expectEqual(dump.get(Ax.focusedWindowAttr)?.windowId, 7)
        expectEqual(dump.get(Ax.focusedWindowAttr)?.ax.containingWindowId(), 7)
    }
}
