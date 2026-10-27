import AppKit
import SwiftUI

private let iconSize = CGSize(width: 50, height: 50)
private let textSize = CGSize(width: 440, height: 110)

final class SecureInputPanel: NSPanelHud {
    private var hostingView: NSHostingView<SecureInputView>?

    /// The hotkeys don't work while secure input is on
    static var isNeeded: Bool {
        guard let activeMode = world.activeMode, world.isEnabled else { return false }
        return config.modes[activeMode]?.bindings.isEmpty == false && world.platform.isSecureInputEnabled
    }

    func refresh() {
        if Self.isNeeded {
            if isVisible { return }
            self.contentView?.subviews.removeAll()
            // A new view on every open, so that it starts minimized
            let hostingView = NSHostingView(rootView: SecureInputView(panel: self))
            self.hostingView = hostingView
            self.contentView?.addSubview(hostingView)
            updateFrame(isMinimized: true)
            self.orderFrontRegardless()
        } else {
            close()
        }
    }

    func updateFrame(isMinimized: Bool) {
        let size = isMinimized ? iconSize : textSize
        hostingView?.frame = NSRect(origin: .zero, size: size)
        self.setFrame(rightEdgeFrame(size: size, y: 20), display: true)
    }
}

struct SecureInputView: View {
    let panel: SecureInputPanel
    @State var isMinimized: Bool = true

    @Environment(\.colorScheme) var colorScheme: ColorScheme
    private var fontColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    var body: some View {
        ZStack(alignment: .center) {
            Rectangle()
                .fill(Color.gray.opacity(isMinimized ? 0.8 : 1.0))
            if isMinimized {
                Image(systemName: "lock.shield.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(6)
            } else {
                Text("AeroSpace cannot respond to keyboard shortcuts while **Secure Input** is active. **Secure Input** is a macOS security feature that prevents applications from reading keyboard events.")
                    .font(.title3)
                    .padding(10)
            }
        }
        .foregroundStyle(fontColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            if !isMinimized {
                panel.refresh()
            }
            isMinimized.toggle()
            panel.updateFrame(isMinimized: isMinimized)
        }
        .frame(
            width: isMinimized ? iconSize.width : textSize.width,
            height: isMinimized ? iconSize.height : textSize.height,
        )
    }
}
