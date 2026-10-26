@MainActor private var lastKnownNativeFocusedWindowId: UInt32? = nil

/// Runs at the start of every session.
/// The data should flow (from nativeFocused to focused) and
///                      (from nativeFocused to lastKnownNativeFocusedWindowId)
/// Alternative names: takeFocusFromMacOs, updateFocusCache
@MainActor func syncFocusFromMacOs() async throws {
    let nativeFocused = try await getNativeFocusedWindow(.cancellable)
    if let nativeFocused { try await debugWindowsIfRecording(nativeFocused, .cancellable) }
    if nativeFocused?.parent is MacosPopupWindowsContainer {
        return
    }
    if nativeFocused?.windowId != lastKnownNativeFocusedWindowId {
        _ = nativeFocused?.focusWindow()
        lastKnownNativeFocusedWindowId = nativeFocused?.windowId
    }
    nativeFocused?.macAppUnsafe.lastNativeFocusedWindowId = nativeFocused?.windowId
}
