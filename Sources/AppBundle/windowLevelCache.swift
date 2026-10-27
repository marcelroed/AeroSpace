import CoreGraphics
import Foundation

/// The levels of the on-screen windows from the last query. Each query replaces it. It's kept across refresh sessions:
/// a cached level is returned without a query
private var cache: [WindowId: MacOsWindowLevel] = [:]

/// Whether the cache was filled in the current refresh session
private var queriedInThisSession = false

/// Call at the start of every refresh session, so that the first miss of the session queries again
func startWindowLevelCacheSession() { queriedInThisSession = false }

func getWindowLevel(for windowId: WindowId) -> MacOsWindowLevel? {
    if let existing = cache[windowId] { return existing }
    // A known window that misses the cache after this session's query is off-screen (minimized, of a hidden app, ...).
    // Don't repeat the query for it in every lookup. A new window may have appeared after the query, so query for it
    if queriedInThisSession && world.windows[windowId] != nil { return nil }

    var result: [WindowId: MacOsWindowLevel] = [:]
    let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
    guard let cfArray = CGWindowListCopyWindowInfo(options, CGWindowID(0)) as? [CFDictionary] else { return nil }
    for elem in cfArray {
        let dict = elem as NSDictionary

        guard let _windowLayer = dict[kCGWindowLayer] else { continue }
        let windowLayer = ((_windowLayer as! CFNumber) as NSNumber).intValue

        guard let _windowId = dict[kCGWindowNumber] else { continue }
        let windowId = WindowId(raw: ((_windowId as! CFNumber) as NSNumber).uint32Value)

        result[windowId] = .new(windowLevel: windowLayer)
    }
    cache = result
    queriedInThisSession = true
    return result[windowId]
}

nonisolated enum MacOsWindowLevel: Sendable, Equatable {
    case normalWindow
    case alwaysOnTopWindow
    case unknown(windowLevel: Int)

    static func new(windowLevel: Int) -> MacOsWindowLevel {
        switch windowLevel {
            case 0: .normalWindow
            case 3: .alwaysOnTopWindow
            default: .unknown(windowLevel: windowLevel)
        }
    }

    static func fromJson(_ json: OrderedJson) -> MacOsWindowLevel? {
        switch json {
            case .string("normalWindow"): .normalWindow
            case .string("alwaysOnTopWindow"): .alwaysOnTopWindow
            case .int(let int): .new(windowLevel: Int(exactly: int).orDie())
            default: nil
        }
    }

    func toJson() -> OrderedJson {
        switch self {
            case .normalWindow: .string("normalWindow")
            case .alwaysOnTopWindow: .string("alwaysOnTopWindow")
            case .unknown(let layerNumber): .int(layerNumber)
        }
    }
}
