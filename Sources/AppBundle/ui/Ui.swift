/// The models of the menu bar and the message window, and the HUD panels: `world.ui`. AeroSpaceApp hands this instance
/// to SwiftUI (``menuBar(_:)``, ``messageWindow(_:)``). The sessions and the commands update it
public final class Ui {
    let trayMenuModel: TrayMenuModel = TrayMenuModel()
    let messageModel: MessageModel = MessageModel()
    /// The panels are windows. They are created when they first show
    lazy var secureInputPanel: SecureInputPanel = SecureInputPanel()
    lazy var volumePanel: VolumePanel = VolumePanel()
}
