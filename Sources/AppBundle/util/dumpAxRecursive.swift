import AppKit
import Common

nonisolated func dumpAxRecursive(_ ax: AXUIElement, _ kind: AxKind, recursionDepth: Int = 0) -> OrderedJson.JsonDict {
    if recursionDepth > 5 {
        return [
            "dumpAxRecursive infinite recursion": .bool(true),
            kAXAeroSynthetic: .bool(true),
        ]
    }
    let recursionDepth = recursionDepth + 1
    var result: OrderedJson.JsonDict = [:]
    var ignored: [String] = []
    var writable: [String] = []
    var failedAxRequest: [String] = []
    var attrNames: CFArray?
    let attrNamesStatus = unsafe AXUIElementCopyAttributeNames(ax, &attrNames)
    if attrNamesStatus != .success {
        failedAxRequest.append("AXUIElementCopyAttributeNames(\(attrNamesStatus.repr))")
    }
    for key: String in attrNames as? [String] ?? [] {
        if globalIgnore.contains(key) || kindSpecificIgnore[kind]?.contains(key) == true {
            ignored.append(key)
        } else {
            var raw: AnyObject?
            let getStatus = unsafe AXUIElementCopyAttributeValue(ax, key as CFString, &raw)
            if getStatus != .success {
                failedAxRequest.append("get.\(key)(\(getStatus.repr))")
            }
            result[key] = prettyValue(raw as Any?, recursionDepth: recursionDepth)

            var isWritable: DarwinBoolean = false
            let isWritableStatus = unsafe AXUIElementIsAttributeSettable(ax, key as CFString, &isWritable)
            if isWritableStatus != .success {
                failedAxRequest.append("isWritable.\(key)(\(isWritableStatus.repr))")
            }
            if isWritable.boolValue { writable.append(key) }
        }
    }
    if !writable.isEmpty { result["Aero.AxWritable"] = .string(writable.joined(separator: ", ")) }
    if !failedAxRequest.isEmpty { result["Aero.AxFailed"] = .string(failedAxRequest.joined(separator: ", ")) }
    if !ignored.isEmpty { result["Aero.AxIgnored"] = .string(ignored.joined(separator: ", ")) }
    return result
}

nonisolated enum AxKind: Hashable {
    case button
    case window
    case app
}

nonisolated func prettyValue(_ value: Any?, recursionDepth: Int) -> OrderedJson {
    if let arr = value as? [Any?] {
        return .array(arr.map { prettyValue($0, recursionDepth: recursionDepth) })
    }
    // AX booleans and numbers are CFBoolean/NSNumber, and all of them convert to Int. So booleans are dumped as 0/1
    if let value = value as? Int {
        return .int(value)
    }
    if let value {
        // Strings, AXValues and other values get here too. `as! AXUIElement` alone wouldn't check the type
        guard CFGetTypeID(value as AnyObject) == AXUIElementGetTypeID() else { return .string(String(describing: value)) }
        let ax = value as! AXUIElement
        if ax.get(Ax.roleAttr) == kAXButtonRole {
            return .dict(dumpAxRecursive(ax, .button, recursionDepth: recursionDepth))
        }
        if let windowId = ax.containingWindowId() {
            let title = ax.get(Ax.titleAttr)?.doubleQuoted ?? "nil"
            let role = ax.get(Ax.roleAttr)?.doubleQuoted ?? "nil"
            let subrole = ax.get(Ax.subroleAttr)?.doubleQuoted ?? "nil"
            return .string("AXUIElement(AxWindowId=\(windowId), title=\(title), role=\(role), subrole=\(subrole))")
        }
        return .string(String(describing: value))
    }
    return .null
}

nonisolated private let globalIgnore: Set<String> = [
    "AXChildren", // too verbose
    "AXChildrenInNavigationOrder", // too verbose
    "AXFocusableAncestor", // infinite recursion
    kAXHelpAttribute, // localized - not helpful
    kAXRoleDescriptionAttribute, // localized - not helpful
]

nonisolated private let kindSpecificIgnore: [AxKind: Set<String>] = [
    .button: [
        "AXFrame",
        kAXEditedAttribute,
        kAXFocusedAttribute,
        kAXPositionAttribute,
        kAXSizeAttribute,
    ],
    .app: [
        "AXEnhancedUserInterface",
        "AXPreferredLanguage",
        kAXHiddenAttribute,
    ],
]

nonisolated extension AXError {
    fileprivate var repr: String {
        switch self {
            case .actionUnsupported: "actionUnsupported"
            case .apiDisabled: "apiDisabled"
            case .attributeUnsupported: "attributeUnsupported"
            case .cannotComplete: "cannotComplete"
            case .failure: "failure"
            case .illegalArgument: "illegalArgument"
            case .invalidUIElement: "invalidUIElement"
            case .invalidUIElementObserver: "invalidUIElementObserver"
            case .noValue: "noValue"
            case .notEnoughPrecision: "notEnoughPrecision"
            case .notImplemented: "notImplemented"
            case .notificationAlreadyRegistered: "notificationAlreadyRegistered"
            case .notificationNotRegistered: "notificationNotRegistered"
            case .notificationUnsupported: "notificationUnsupported"
            case .parameterizedAttributeUnsupported: "parameterizedAttributeUnsupported"
            case .success: "success"
            @unknown default: rawValue.description
        }
    }
}
