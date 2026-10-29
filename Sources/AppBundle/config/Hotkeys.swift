import AppKit
import Common
import Foundation
import HotKey

/// The registered global hotkeys by key code. Only the active mode's ones are enabled
private final class Hotkeys {
    private var byKeyCode: [String: HotKey] = [:]

    func reset() {
        // Explicitly unregister all hotkeys. We cannot always rely on destruction of the HotKey object to trigger
        // unregistration because we might be running inside a hotkey handler that is keeping its HotKey object alive.
        for (_, key) in byKeyCode {
            key.isEnabled = false
        }
        byKeyCode = [:]
    }

    /// Registers the missing hotkeys of `mode` and pauses all others. Never suspends
    func register(for mode: String?) {
        let bindings = mode.flatMap { config.modes[$0] }?.bindings ?? [:]
        for binding in bindings.values where byKeyCode[binding.descriptionWithKeyCode] == nil {
            checkIsAeroSpaceApp("The global hotkey \(binding.descriptionWithKeyNotation)")
            // swiftlint:disable:next live_effect
            byKeyCode[binding.descriptionWithKeyCode] = HotKey(key: binding.keyCode, modifiers: binding.modifiers, keyDownHandler: {
                Task.startUnstructured { try await onHotkeyPressed(binding) }
            })
        }
        for (keyCode, hotkey) in byKeyCode {
            hotkey.isEnabled = bindings.keys.contains(keyCode)
        }
    }
}

private let hotkeys = Hotkeys()

func resetHotKeys() { hotkeys.reset() }
func registerHotkeys(for mode: String?) { hotkeys.register(for: mode) }

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

func activateMode_nonCancellable(_ targetMode: String?) async {
    registerHotkeys(for: targetMode)
    let oldMode = world.activeMode
    world.activeMode = targetMode
    if oldMode != targetMode {
        broadcastEvent(.modeChanged(mode: targetMode))
        _ = await config.onModeChanged.run(.defaultEnv, .emptyStdin)
    }
}


/// Runs the binding of the *current* config and mode with the pressed key
private func onHotkeyPressed(_ binding: HotkeyBinding) async throws {
    // `enable off` pauses the hotkeys and clears the active mode, so a press that was already on its way stops here
    guard let activeMode = world.activeMode, let token: RunSessionGuard = .isServerEnabled else { return }
    // The HotKey is registered by the first mode that binds the key code. Another mode can bind the same
    // key code with another notation (e.g. 'shift-alt-a' and 'alt-shift-a')
    func currentBinding() -> HotkeyBinding? { config.modes[activeMode]?.bindings[binding.descriptionWithKeyCode] }
    broadcastEvent(.bindingTriggered(mode: activeMode, binding: (currentBinding() ?? binding).descriptionWithKeyNotation))
    // The config may reload at the light session's suspension points before the body
    try await world.sessions.light(.hotkeyBinding, token) { () throws in
        _ = await currentBinding()?.commands.run(.defaultEnv, .emptyStdin)
    }
}
