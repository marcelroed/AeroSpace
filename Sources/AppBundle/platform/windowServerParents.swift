import AppKit

/// The window server parent of each window that has one (see ``Platform/windowServerParents(_:)``), in one query of the
/// window server (~0.1 ms for 15 windows). Neither AX nor CoreGraphics' public API tells it, so this asks SkyLight, the
/// private framework under CoreGraphics, the way yabai does. It's looked up at runtime, so that the binary doesn't link a
/// private framework: if a macOS update drops a symbol, no window has a parent, and the popups stay where their apps put
/// them, as before
nonisolated func windowServerParents(_ ids: [UInt32]) -> [UInt32: UInt32] {
    guard let skyLight = SkyLight.shared, !ids.isEmpty else { return [:] }
    let windows = ids.map { NSNumber(value: $0) } as CFArray
    guard let query = unsafe skyLight.queryWindows(skyLight.connection, windows, Int32(ids.count))?.takeRetainedValue(),
          let iterator = unsafe skyLight.queryResultCopyWindows(query)?.takeRetainedValue()
    else { return [:] }
    var result: [UInt32: UInt32] = [:]
    while skyLight.iteratorAdvance(iterator) {
        let parent = skyLight.iteratorGetParentId(iterator)
        if parent != 0 {
            result[skyLight.iteratorGetWindowId(iterator)] = parent
        }
    }
    return result
}

/// The SkyLight functions of ``windowServerParents(_:)``
@safe nonisolated private struct SkyLight: @unchecked Sendable {
    typealias QueryWindows = @convention(c) (Int32, CFArray, Int32) -> Unmanaged<CFTypeRef>?
    typealias QueryResultCopyWindows = @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?
    typealias IteratorAdvance = @convention(c) (CFTypeRef) -> Bool
    typealias IteratorGetId = @convention(c) (CFTypeRef) -> UInt32

    let connection: Int32
    let queryWindows: QueryWindows
    let queryResultCopyWindows: QueryResultCopyWindows
    let iteratorAdvance: IteratorAdvance
    let iteratorGetWindowId: IteratorGetId
    let iteratorGetParentId: IteratorGetId

    /// nil if a symbol is missing
    static let shared: SkyLight? = {
        guard let handle = unsafe dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else { return nil }
        func symbol<T>(_ name: String, _: T.Type) -> T? {
            unsafe dlsym(handle, name).map { unsafe unsafeBitCast($0, to: T.self) }
        }
        guard let mainConnectionId = symbol("SLSMainConnectionID", (@convention(c) () -> Int32).self),
              let queryWindows = unsafe symbol("SLSWindowQueryWindows", QueryWindows.self),
              let queryResultCopyWindows = unsafe symbol("SLSWindowQueryResultCopyWindows", QueryResultCopyWindows.self),
              let iteratorAdvance = symbol("SLSWindowIteratorAdvance", IteratorAdvance.self),
              let iteratorGetWindowId = symbol("SLSWindowIteratorGetWindowID", IteratorGetId.self),
              let iteratorGetParentId = symbol("SLSWindowIteratorGetParentID", IteratorGetId.self)
        else { return nil }
        return unsafe SkyLight(
            connection: mainConnectionId(),
            queryWindows: queryWindows,
            queryResultCopyWindows: queryResultCopyWindows,
            iteratorAdvance: iteratorAdvance,
            iteratorGetWindowId: iteratorGetWindowId,
            iteratorGetParentId: iteratorGetParentId,
        )
    }()
}
