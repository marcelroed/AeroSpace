@testable import AppBundle
import AppKit
import Common
import Testing

@Suite
struct AxUiElementWindowTypeTest {
    @Test
    func testAxDumpsExist() throws {
        #expect(try axDumpPaths().count > 0)
    }

    // Each dump is its own test case: a malformed dump fails its case instead of crashing the whole test run
    @Test(arguments: try axDumpPaths())
    func testAxDump(_ path: String) throws {
        try checkAxDump(axDumpsDir.appending(path: path))
    }

    // A malformed dump must fail only its own case. Dying on these values would crash the whole test run
    @Test
    func testMalformedDumpValuesAreRejectedWithoutDying() {
        expectEqual(OrderedJson.newOrNilRecursive(["x": 1.5] as [String: Any]), nil)
        expectEqual(OrderedJson.newOrNilRecursive(["x": [1, 2.5]] as [String: Any]), nil)
        expectEqual(OrderedJson.newOrNilRecursive(["x": UInt.max] as [String: Any]), nil) // JSONSerialization gives UInt above Int64.max
        expectEqual(OrderedJson.newOrNilRecursive(["x": [1, "a"]] as [String: Any]), .dict(["x": .array([.int(1), .string("a")])]))
        #expect(axUiElementMockFromTestDump(NSNumber(value: 5)) == nil)
        #expect(axUiElementMockFromTestDump("garbage, not an element" as NSString) == nil)
    }

    /// RB-85: the level comes from the on-screen windows only. A Chrome window first seen off-screen (minimized, of a hidden
    /// app) has no level, which must not make it a popup. A level other than normal still does
    @Test
    func testUnknownWindowLevelIsNotAPopup() throws {
        let file = axDumpsDir.appending(path: "chrome.json5")
        let rawJson = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: file), options: [.json5Allowed]) as? [String: Any],
        )
        let json = try #require(OrderedJson.newOrNilRecursive(rawJson)?.asDictOrNil)
        let app = try #require(json["Aero.AXApp"]?.asDictOrNil)
        expectEqual(json.getWindowType(axApp: app, .chrome, .regular, .normalWindow), .window)
        expectEqual(json.getWindowType(axApp: app, .chrome, .regular, nil), .window)
        expectEqual(json.getWindowType(axApp: app, .chrome, .regular, .alwaysOnTopWindow), .popup)
    }

    // debug-windows writes the activation policy with prettyDescription, and the dumps are read back with from(string:)
    @Test
    func testActivationPolicyRoundTrip() {
        for policy: NSApplication.ActivationPolicy in [.regular, .accessory, .prohibited] {
            let string = policy.prettyDescription
            expectEqual(NSApplication.ActivationPolicy.from(string: string), policy, "\(string.singleQuoted)")
        }
    }
}

nonisolated private let axDumpsDir = projectRoot.appending(path: "./axDumps")

/// Paths relative to `axDumpsDir`
nonisolated private func axDumpPaths() throws -> [String] {
    try FileManager.default.subpathsOfDirectory(atPath: axDumpsDir.path())
        .filter { !axDumpsDir.appending(path: $0).isDirectory && !$0.hasSuffix(".md") }
        .sorted()
}

private func checkAxDump(_ file: URL) throws {
    let rawJson = try #require(
        try JSONSerialization.jsonObject(with: Data.init(contentsOf: file), options: [.json5Allowed]) as? [String: Any],
        "The dump isn't a JSON object",
    )
    let json = try #require(OrderedJson.newOrNilRecursive(rawJson)?.asDictOrNil, "The dump contains a value that OrderedJson can't represent")
    let app = try #require(json["Aero.AXApp"]?.asDictOrNil, "Aero.AXApp is missing or isn't an object")
    let appBundleId = (rawJson["Aero.App.appBundleId"] as? String).flatMap { KnownBundleId.init(rawValue: $0) }
    let windowLevel = try json["Aero.windowLevel"].map { try #require(MacOsWindowLevel.fromJson($0), "Invalid Aero.windowLevel") }
    let activationPolicy = try #require(
        (rawJson["Aero.App.nsApp.activationPolicy"] as? String).flatMap(NSApplication.ActivationPolicy.from(string:)),
        "Aero.App.nsApp.activationPolicy is missing or unknown",
    )
    let expectedWindowType = try #require(
        (rawJson["Aero.AxUiElementWindowType"] as? String).flatMap(AxUiElementWindowType.init(rawValue:)),
        "Aero.AxUiElementWindowType is missing or unknown",
    )
    let expectedIsDialogHeuristic = try #require(
        rawJson["Aero.AxUiElementWindowType_isDialogHeuristic"] as? Bool,
        "Aero.AxUiElementWindowType_isDialogHeuristic is missing",
    )
    expectEqual(
        json.getWindowType(axApp: app, appBundleId, activationPolicy, windowLevel),
        expectedWindowType,
        "\(file.path()):0:0: AxUiElementWindowType doesn't match",
    )
    expectEqual(
        json.isDialogHeuristic(appBundleId, windowLevel),
        expectedIsDialogHeuristic,
        "\(file.path()):0:0: AxUiElementWindowType_isDialogHeuristic doesn't match",
    )
}

/// Reports a malformed dump as an issue of the current test case. `dieT` would crash all tests
private func recordIssue<T>(_ message: String) -> T? {
    Issue.record(Comment(rawValue: message))
    return nil
}

extension OrderedJson.JsonDict: AxUiElementMock {
    public func get<Attr>(_ attr: Attr) -> Attr.T? where Attr: ReadableAttr {
        guard let value = self[attr.key] else {
            return isSynthetic ? recordIssue("\(self) doesn't contain \(attr.key)") : nil
        }
        guard let value = value.rawValue else { return nil }
        // A nested element. AX gives the attribute's getter an AXUIElement, a dump gives a dictionary or a string
        if let element = axUiElementMockFromTestDump(value as AnyObject) {
            if let element = element as? Attr.T { return element } // Ax.closeButtonAttr and the like
            if Attr.T.self == WindowIdAndAxUiElementMock.self { // Ax.focusedWindowAttr
                return element.containingWindowId().map { (windowId: $0, ax: element) } as? Attr.T
            }
        }
        return attr.getter(value as AnyObject)
            ?? recordIssue("Value \(value) (of type \(Swift.type(of: value))) isn't convertible to \(attr.key)")
    }

    private var isSynthetic: Bool { self[kAXAeroSynthetic] != nil }

    public func containingWindowId() -> CGWindowID? {
        guard let windowId = self["Aero.axWindowId"]?.asInt64OrNil else { return recordIssue("\(self) doesn't contain Aero.axWindowId") }
        return UInt32.init(exactly: windowId) ?? recordIssue("Aero.axWindowId \(windowId) isn't a window ID")
    }
}

extension NSApplication.ActivationPolicy {
    static func from(string: String) -> NSApplication.ActivationPolicy? {
        switch string {
            case "regular": .regular
            case "accessory": .accessory
            case "prohibited": .prohibited
            default: nil
        }
    }
}

nonisolated extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}

/// AX elements in JSON dumps: either dictionaries or "AXUIElement(AxWindowId=…" strings. nil for any other value (a
/// malformed dump), so that the test of that dump fails instead of the whole test run
nonisolated func axUiElementMockFromTestDump(_ a: AnyObject) -> (any AxUiElementMock)? {
    if let str = a as? String, let commaIndex = str.firstIndex(of: ",") {
        let windowId = UInt32.init(String(str.prefix(upTo: commaIndex)).removePrefix("AXUIElement(AxWindowId="))
        if let windowId {
            let dict: OrderedJson.JsonDict = ["Aero.axWindowId": .int(windowId), kAXAeroSynthetic: .bool(true)]
            return axUiElementMockFromTestDump(dict as AnyObject)
        }
    }
    if let dict = a as? OrderedJson.JsonDict { // Unbox from __SwiftValue
        return dict
    }
    return nil
}
