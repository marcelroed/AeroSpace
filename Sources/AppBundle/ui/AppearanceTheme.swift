import SwiftUI

enum AppearanceTheme {
    case light
    case dark

    /// System Settings -> Appearance -> Light/Dark
    /// This is the theme representing how the UI should look inside the app (this might be different than the menu bar color)
    static var current: AppearanceTheme {
        let darkNames: [NSAppearance.Name] = [.vibrantDark, .darkAqua, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]
        return darkNames.contains(NSApplication.shared.effectiveAppearance.name) ? .dark : .light
    }
}
