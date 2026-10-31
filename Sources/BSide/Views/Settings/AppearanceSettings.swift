import ServiceManagement
import SwiftUI

/// Light or dark, and the size of everything in the window: one section
/// of General.
struct AppearanceSection: View {
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
        Section {
            Picker(selection: themeMode) {
                ForEach(ThemeMode.allCases) { Text($0.title).tag($0) }
            } label: {
                SettingLabel(title: "Theme", symbol: "circle.lefthalf.filled", colour: 1)
            }
            .pickerStyle(.segmented)
            Picker(selection: uiSize) {
                ForEach(UISize.allCases) { Text($0.title).tag($0) }
            } label: {
                SettingLabel(title: "Text and buttons", symbol: "textformat.size", colour: 3)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Appearance")
        } footer: {
            Text("Automatic follows the system. Medium and Large are 15% and 30% bigger; the window itself drags to any size.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
