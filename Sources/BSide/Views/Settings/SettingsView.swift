import ServiceManagement
import SwiftUI

/// The standard macOS settings window: Command-comma, tabs in the toolbar
/// (SettingsWindow puts them there), grouped forms, system controls in
/// B-Side's orange, and each setting with a small icon in one of the Vibe
/// colours, as System Settings has them. This is one tab's pane.
struct SettingsView: View {
    enum Tab: String, CaseIterable {
        case general, appearance, playback, vibes, account, diagnostics

        var title: String { rawValue.capitalized }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .appearance: "paintpalette"
            case .playback: "play.circle"
            case .vibes: "text.bubble"
            case .account: "person.crop.circle"
            case .diagnostics: "gauge.with.dots.needle.33percent"
            }
        }
    }

    var tab: Tab = .general

    var body: some View {
        Group {
            switch tab {
            case .general: GeneralSettings()
            case .appearance: AppearanceSettings()
            case .playback: PlaybackSettings()
            case .vibes: VibeSettings()
            case .account: AccountSettings()
            case .diagnostics: DiagnosticsSettings()
            }
        }
        .frame(width: Theme.Size.settingsWidth)
        .tint(Theme.Colors.accent)
    }
}

/// Settings' forms scroll with the thin scrollers that show only while
/// scrolling, as the main window's lists do, whatever "Show scroll bars"
/// says: the wide kind took the eye from the settings. The form's scroll
/// view is not this view's ancestor, so it is looked for in the window.
struct ThinScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Finder() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Finder: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // After SwiftUI has built the form.
            DispatchQueue.main.async { [weak self] in
                guard let root = self?.window?.contentView else { return }
                Self.thin(in: root)
            }
        }

        private static func thin(in view: NSView) {
            if let scroll = view as? NSScrollView { scroll.scrollerStyle = .overlay }
            view.subviews.forEach(thin(in:))
        }
    }
}

/// "B-Side Settings" as the window's title on every tab: SwiftUI's settings
/// window would repeat the tab's name there.
/// A setting's name with its icon: a white symbol on a small rounded square
/// in one of VibePalette's gradients.
struct SettingLabel: View {
    let title: String
    let symbol: String
    let colour: Int

    var body: some View {
        let swatch = VibePalette.swatches[colour]
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .font(Theme.Text.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.onVibe)
                .frame(width: Theme.Size.settingIcon, height: Theme.Size.settingIcon)
                .background(LinearGradient(colors: [swatch.light, swatch.deep], startPoint: .topTrailing, endPoint: .bottomLeading),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.s))
        }
    }
}
