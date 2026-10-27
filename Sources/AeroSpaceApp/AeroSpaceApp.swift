import AppBundle
import SwiftUI

// This file is shared between SPM and xcode project

@main
struct AeroSpaceApp: App {
    @Environment(\.openWindow) private var openWindow: OpenWindowAction

    init() {
        initAppBundle()
    }

    var body: some Scene {
        menuBar(viewModel: .shared)
        getMessageWindow(messageModel: .shared)
            .onChange(of: MessageModel.shared.message) { _, message in
                if message != nil {
                    openWindow(id: messageWindowId)
                }
            }
    }
}
