import ServiceManagement
import SwiftUI

/// Light or dark, and the size of everything in the window.
struct AppearanceSettings: View {
    @AppStorage(Keys.theme) private var theme = ThemeMode.system.rawValue
    @AppStorage(Keys.uiSize) private var size = UISize.compact.rawValue

    private var themeMode: Binding<ThemeMode> {
        Binding {
            ThemeMode(rawValue: theme) ?? .system
        } set: { mode in
            theme = mode.rawValue
            ThemeMode.apply(mode)
        }
    }

    /// Theme's scale changes first, so the window is built again at the new size.
    private var uiSize: Binding<UISize> {
        Binding {
            UISize(rawValue: size) ?? .compact
        } set: { new in
            Theme.scale = new.scale
            size = new.rawValue
        }
    }

    var body: some View {
        Form {
            Section {
                Picker(selection: themeMode) {
                    ForEach(ThemeMode.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingLabel(title: "Appearance", symbol: "circle.lefthalf.filled", colour: 1)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Automatic follows the system's light and dark setting.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker(selection: uiSize) {
                    ForEach(UISize.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingLabel(title: "Size", symbol: "textformat.size", colour: 3)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Large makes the window, its text and its buttons 30% bigger, for reading at a distance or with low vision.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .background(ThinScrollers())
    }
}
