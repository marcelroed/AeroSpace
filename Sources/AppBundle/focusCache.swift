/// Runs at the start of every session.
/// The data should flow (from nativeFocused to focused) and
///                      (from nativeFocused to lastKnownNativeFocusedWindowId)
/// Alternative names: takeFocusFromMacOs, updateFocusCache
func syncFocusFromMacOs() async throws(CancellationError) {
    let nativeFocused = try await getNativeFocusedWindow()
    if let nativeFocused { await debugWindowsIfRecording(nativeFocused) }
    if case .macosPopup = nativeFocused?.placement {
        return
    }
    // No screens (e.g., during display reconfiguration): setFocus can't show invisible workspaces meanwhile. Don't consume
    // the native focus change, the first session after the screens come back takes it
    if nativeFocused?.windowId != world.focusStore.lastKnownNativeFocusedWindowId && world.monitors.hasScreens {
        _ = nativeFocused?.focusWindow()
        world.focusStore.lastKnownNativeFocusedWindowId = nativeFocused?.windowId
    }
}
