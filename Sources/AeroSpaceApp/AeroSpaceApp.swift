import AppBundle
import SwiftUI

// This file is shared between SPM and xcode project

@main
struct AeroSpaceApp: App {
    private let ui: Ui

    init() {
        ui = initAppBundle()
    }

    var body: some Scene {
        menuBar(ui)
        messageWindow(ui)
    }
}
