import ServiceManagement
import SwiftUI

/// Light or dark, and the size of everything in the window.
struct AppearanceSettings: View {
    @AppStorage(Keys.theme) private var theme = ThemeMode.system.rawValue
    @AppStorage(Keys.uiScale, store: Settings.defaults) private var scale = 0.0

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
            _ = scale // read, so the picker follows a change of the size
            return UISize.nearest(Theme.scale)
        } set: { new in
            WindowSize.set(new.scale)
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
                Text("Large makes the text and the buttons 30% bigger, for reading at a distance or with low vision. The window itself can be dragged to any size.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .background(ThinScrollers())
    }
}
