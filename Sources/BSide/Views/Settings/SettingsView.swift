import ServiceManagement
import SwiftUI

/// The standard macOS settings window: Command-comma, tabs, grouped forms,
/// system controls in B-Side's orange, and each setting with a small icon in
/// one of the Vibe colours, as System Settings has them.
struct SettingsView: View {
    enum Tab: String, CaseIterable {
        case general, appearance, playback, vibes, account, diagnostics
    }

    @State private var tab: Tab

    init(tab: Tab = .general) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
                .tag(Tab.appearance)
            PlaybackSettings()
                .tabItem { Label("Playback", systemImage: "play.circle") }
                .tag(Tab.playback)
            VibeSettings()
                .tabItem { Label("Vibes", systemImage: "text.bubble") }
                .tag(Tab.vibes)
            AccountSettings()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(Tab.account)
            DiagnosticsSettings()
                .tabItem { Label("Diagnostics", systemImage: "gauge.with.dots.needle.33percent") }
                .tag(Tab.diagnostics)
        }
        .frame(width: Theme.Size.settingsWidth)
        .tint(Theme.Colors.accent)
        .background(SettingsTitle())
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
private struct SettingsTitle: NSViewRepresentable {
    static let title = "B-Side Settings"

    func makeNSView(context: Context) -> NSView { TitleKeeper() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class TitleKeeper: NSView {
        private var watch: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return watch = nil }
            (window.contentViewController as? NSTabViewController)?.canPropagateSelectedChildViewControllerTitle = false
            window.title = SettingsTitle.title
            // A tab change may still set it; set it back.
            watch = window.observe(\.title, options: [.new]) { window, _ in
                MainActor.assumeIsolated {
                    if window.title != SettingsTitle.title { window.title = SettingsTitle.title }
                }
            }
        }
    }
}

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
