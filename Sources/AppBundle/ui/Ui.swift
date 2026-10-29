/// The models of the menu bar and the message window, and the HUD panels: `world.ui`. AeroSpaceApp hands this instance
/// to SwiftUI (``menuBar(_:)``, ``messageWindow(_:)``). The sessions and the commands update it
public final class Ui {
    let trayMenuModel: TrayMenuModel = TrayMenuModel()
    let messageModel: MessageModel = MessageModel()
    /// The panels are windows. They are created when they first show
    private var secureInputPanel: SecureInputPanel? = nil
    lazy var volumePanel: VolumePanel = VolumePanel()

    func refreshSecureInputPanel() {
        if secureInputPanel == nil && !SecureInputPanel.isNeeded { return }
        let panel = secureInputPanel ?? SecureInputPanel()
        secureInputPanel = panel
        panel.refresh()
    }
}
