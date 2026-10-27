import Common
import Observation
import SwiftUI

/// The config diagnostics window
public func messageWindow(_ ui: Ui) -> some Scene {
    // Using SwiftUI.Window because another class in AeroSpace is already called Window
    SwiftUI.Window(aeroSpaceAppName, id: messageWindowId) {
        MessageView(model: ui.messageModel, trayMenuModel: ui.trayMenuModel)
            .onAppear {
                // Set activation policy; otherwise, AeroSpace windows won't be able to receive focus and accept keyboard input
                NSApp.setActivationPolicy(.accessory)
            }
            .windowMinimizeBehavior(.disabled) // Disable minimize button, because we don't unminimize the window on config error
    }
    .windowResizability(.contentMinSize)
    .windowLevel(.floating)
}

let messageWindowId: String = "\(aeroSpaceAppName).messageView"

struct MessageView: View {
    let model: MessageModel
    let trayMenuModel: TrayMenuModel
    @Environment(\.dismiss) private var dismiss: DismissAction
    @FocusState private var focus: Bool

    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .center) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 48))
                Text(verbatim: model.message == nil ? "" : "AeroSpace Config Diagnostics")
                    .padding(.horizontal)
                    .focusable()
            }
            .padding()
            ScrollView {
                VStack(alignment: .leading) {
                    HStack {
                        let cancelOnEnterBinding: Binding<String> = Binding(
                            get: { model.message?.body ?? "" },
                            set: { newText in
                                if let prev = model.message?.body.count(where: \.isNewline), newText.count(where: \.isNewline) > prev {
                                    model.message = nil
                                }
                            },
                        )
                        TextEditor(text: cancelOnEnterBinding)
                            .font(.system(size: 12).monospaced())
                            .focused($focus)
                        Spacer()
                    }
                    Spacer()
                }
                .padding()
            }
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal)
            HStack {
                Spacer()
                if model.message != nil {
                    reloadConfigButton(trayMenuModel, showShortcutGroup: true)
                    openConfigButton(showShortcutGroup: true)
                }
                let closeButton = Button("Close") { model.message = nil }.keyboardShortcut(.defaultAction)
                shortcutGroup(label: Image(systemName: "return.left"), content: closeButton)
            }
            .padding()
        }
        .textSelection(.enabled)
        .frame(minWidth: 480, maxWidth: 960, minHeight: 200)
        .onChange(of: model.message) { _, message in
            if message == nil {
                self.dismiss()
            }
        }
        .onDisappear {
            // If user closes the screen with the macOS native close (x) button and then the error is still the same, this window will not appear again
            model.message = nil
        }
        .onAppear {
            focus = true
        }
    }
}

@Observable
final class MessageModel {
    var message: Message? = nil
}

/// A config diagnostics message
struct Message: Hashable {
    let body: String
}
