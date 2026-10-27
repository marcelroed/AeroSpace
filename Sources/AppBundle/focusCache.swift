/// Takes the focus from macOS: the window that has the native focus becomes the focused window, once per change of the
/// native focus. A popup doesn't take the focus.
/// The data should flow (from nativeFocused to focused) and
///                      (from nativeFocused to lastKnownNativeFocusedWindowId)
/// Alternative names: takeFocusFromMacOs, updateFocusCache
func syncFocusFromMacOs(_ nativeFocused: Window?) {
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
