import SwiftUI

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case monospacedText
    case systemText
    case squares
    case i3
    case i3Ordered
    var id: String { rawValue }
    var title: String {
        switch self {
            case .monospacedText: "Monospaced font"
            case .systemText: "System font"
            case .squares: "Square images"
            case .i3: "i3 style grouped"
            case .i3Ordered: "i3 style ordered"
        }
    }
}

@MainActor
func getExperimentalUISettingsMenu(viewModel: TrayMenuModel) -> some View {
    let color = viewModel.appearanceTheme == .dark ? Color.white : Color.black
    return Menu {
        Text("Menu bar style (macOS 14 or later):")
        ForEach(MenuBarStyle.allCases) { style in
            Button {
                viewModel.menuBarStyle = style
            } label: {
                Toggle(isOn: .constant(viewModel.menuBarStyle == style)) {
                    MenuBarLabel(style: style, color: color)
                        .environmentObject(viewModel)
                    Text(" -  " + style.title)
                }
            }
        }
    } label: {
        Text("Experimental UI Settings (No stability guarantees)")
    }
}
