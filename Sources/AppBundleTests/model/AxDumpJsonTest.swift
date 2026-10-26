@testable import AppBundle
import AppKit
import Common
import Testing

/// Pins the JSON that `debug-windows` prints, and how unit tests read the committed `axDumps` back
@Suite
struct AxDumpJsonTest: AeroSpaceTestSuite {
    /// Encoded the same way as in `dumpWindowDebugInfo`
    @Test
    func testEncode() {
        var result: [String: Json] = [:]
        result["Aero.AXApp"] = .dict(["AXRole": .string("AXApplication"), "AXEnabled": .int(1), "AXEmpty": .dict([:])])
        result["Aero.on-window-detected"] = .array([.dict(["commands": .string("layout floating")]), .array([])])
        result["Aero.workspace"] = .null
        result["Aero.AxUiElementWindowType_isDialogHeuristic"] = .bool(false)
        result["Aero.axWindowId"] = .int(42)
        result["Aero.App.nsApp.appBundlePath"] = .string("file:///Applications/Foo%20Bar.app/ \"é\" 🙂")
        assertEquals(
            JSONEncoder.aeroSpaceDefault.encodeToString(result),
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
        func pretty(_ raw: AnyObject?) -> Json { prettyValue(raw as Any?, recursionDepth: 1) }
        assertEquals(pretty(kCFBooleanTrue), .int(1))
        assertEquals(pretty(kCFBooleanFalse), .int(0))
        assertEquals(pretty(NSNumber(value: true)), .int(1))
        assertEquals(pretty(NSNumber(value: UInt32.max)), .int(Int64(UInt32.max)))
        assertEquals(pretty(NSArray(array: [kCFBooleanTrue.orDie(), NSNumber(value: 7)])), .array([.int(1), .int(7)]))
        assertEquals(pretty(nil), .null)
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
        let dump = Json.newOrDieRecursive(raw).asDictOrDie
        assertEquals(dump["AXEnabled"], .int(1))
        assertEquals(dump["AXFocused"], .int(0))
        assertEquals(dump["AXTitle"], .string("a/b"))
        assertEquals(dump["AXIdentifier"], .null)
        assertEquals(dump["AXSections"], .array([.int(0), .dict(["k": .string("v")])]))

        assertEquals(dump.get(Ax.enabledAttr), true)
        assertEquals(dump.get(Ax.isFocused), false)
        assertEquals(dump.get(Ax.titleAttr), "a/b")
        assertNil(dump.get(Ax.identifierAttr))
        assertNil(dump.get(Ax.subroleAttr)) // Missing keys are nil, unless the dump is synthetic
        assertEquals(dump.containingWindowId(), 5)
        assertEquals(dump.get(Ax.closeButtonAttr)?.get(Ax.roleAttr), "AXButton")
        assertEquals(dump.get(Ax.closeButtonAttr)?.get(Ax.enabledAttr), true)
        assertEquals(dump.get(Ax.focusedWindowAttr)?.windowId, 7)
        assertEquals(dump.get(Ax.focusedWindowAttr)?.ax.containingWindowId(), 7)
    }
}
