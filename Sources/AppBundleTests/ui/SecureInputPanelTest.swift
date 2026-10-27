@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct SecureInputPanelTest {
    /// The panel tells the user that the hotkeys don't work. Only its need is tested: a test creates no panel
    @Test
    func thePanelIsNeededWhileSecureInputBlocksTheActiveModesBindings() {
        let binding = HotkeyBinding(.option, .h, parseCommand("focus left").cmdOrDie)
        world.config.modes = [mainModeId: Mode(bindings: [binding.descriptionWithKeyCode: binding])]
        fake.isSecureInputEnabled = true
        #expect(SecureInputPanel.isNeeded)

        world.isEnabled = false
        #expect(!SecureInputPanel.isNeeded, "AeroSpace is disabled")
        world.isEnabled = true
        world.config.modes = [mainModeId: Mode(bindings: [:])]
        #expect(!SecureInputPanel.isNeeded, "the active mode has no bindings")
    }
}
