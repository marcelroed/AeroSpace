import AppBundle
import SwiftUI

// This file is shared between SPM and xcode project

@main
struct AeroSpaceApp: App {
    init() {
        initAppBundle()
    }

    var body: some Scene {
        menuBar(viewModel: .shared, messageModel: .shared)
        getMessageWindow(messageModel: .shared)
    }
}
