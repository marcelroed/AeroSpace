/// Runs at the start of every session.
/// The data should flow (from nativeFocused to focused) and
///                      (from nativeFocused to lastKnownNativeFocusedWindowId)
/// Alternative names: takeFocusFromMacOs, updateFocusCache
func syncFocusFromMacOs() async throws {
    let nativeFocused = try await getNativeFocusedWindow(.cancellable)
    if let nativeFocused { try await debugWindowsIfRecording(nativeFocused, .cancellable) }
    if case .macosPopup = nativeFocused?.placement {
        return
    }
    // No screens (e.g., during display reconfiguration): setFocus can't show invisible workspaces meanwhile. Don't consume
    // the native focus change, the first session after the screens come back takes it
    if nativeFocused?.windowId != world.focusStore.lastKnownNativeFocusedWindowId && hasScreens {
        _ = nativeFocused?.focusWindow()
        world.focusStore.lastKnownNativeFocusedWindowId = nativeFocused?.windowId
    }
    nativeFocused?.asMacWindow().macApp.lastNativeFocusedWindowId = nativeFocused?.windowId
}
