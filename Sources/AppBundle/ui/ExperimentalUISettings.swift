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

func getExperimentalUISettingsMenu(viewModel: TrayMenuModel) -> some View {
    let color = viewModel.appearanceTheme == .dark ? Color.white : Color.black
    return Menu {
        Text("Menu bar style:")
        ForEach(MenuBarStyle.allCases) { style in
            MenuBarStyleButton(viewModel: viewModel, style: style, color: color)
        }
    } label: {
        Text("Experimental UI Settings (No stability guarantees)")
    }
}

// Keep this a separate View whose body reads viewModel.menuBarStyle: that is what redraws the checkmark after a selection.
// Inlined into the menu, the checkmark stayed on the old style (f26736bf)
struct MenuBarStyleButton: View {
    let viewModel: TrayMenuModel
    let style: MenuBarStyle
    let color: Color

    var body: some View {
        Button {
            viewModel.menuBarStyle = style
        } label: {
            Toggle(isOn: .constant(viewModel.menuBarStyle == style)) {
                MenuBarLabel(viewModel: viewModel, style: style, color: color)
                Text(" -  " + style.title)
            }
        }
    }
}
