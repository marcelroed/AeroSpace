import AppKit
import Common
import Foundation
import HotKey

private var hotkeys: [String: HotKey] = [:]

func resetHotKeys() {
    // Explicitly unregister all hotkeys. We cannot always rely on destruction of the HotKey object to trigger
    // unregistration because we might be running inside a hotkey handler that is keeping its HotKey object alive.
    for (_, key) in hotkeys {
        key.isEnabled = false
    }
    hotkeys = [:]
}

extension HotKey {
    var isEnabled: Bool {
        get { !isPaused }
        set {
            if isEnabled != newValue {
                isPaused = !newValue
            }
        }
    }
}

var activeMode: String? = mainModeId
func activateMode_nonCancellable(_ targetMode: String?) async {
    registerHotkeys(for: targetMode)
    let oldMode = activeMode
    activeMode = targetMode
    if oldMode != targetMode {
        broadcastEvent(.modeChanged(mode: targetMode))
        _ = await config.onModeChanged.run(.defaultEnv, .emptyStdin)
    }
}

/// Registers the missing hotkeys of `mode` and pauses all others. Never suspends
func registerHotkeys(for mode: String?) {
    let bindings = mode.flatMap { config.modes[$0] }?.bindings ?? [:]
    for binding in bindings.values where hotkeys[binding.descriptionWithKeyCode] == nil {
        hotkeys[binding.descriptionWithKeyCode] = HotKey(key: binding.keyCode, modifiers: binding.modifiers, keyDownHandler: {
            Task.startUnstructured { try await onHotkeyPressed(binding) }
        })
    }
    for (keyCode, hotkey) in hotkeys {
        hotkey.isEnabled = bindings.keys.contains(keyCode)
    }
}

/// Runs the binding of the *current* config and mode with the pressed key
private func onHotkeyPressed(_ binding: HotkeyBinding) async throws {
    guard let activeMode else { return }
    // The HotKey is registered by the first mode that binds the key code. Another mode can bind the same
    // key code with another notation (e.g. 'shift-alt-a' and 'alt-shift-a')
    let activeBinding = config.modes[activeMode]?.bindings[binding.descriptionWithKeyCode]
    broadcastEvent(.bindingTriggered(mode: activeMode, binding: (activeBinding ?? binding).descriptionWithKeyNotation))
    try await runLightSession(.hotkeyBinding, .isServerEnabled ?? dieT("server is disabled")) { () throws in
        _ = await config.modes[activeMode]?.bindings[binding.descriptionWithKeyCode]?.commands.run(.defaultEnv, .emptyStdin)
    }
}
