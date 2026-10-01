import ServiceManagement
import SwiftUI

/// The standard macOS settings window: Command-comma, tabs, grouped forms,
/// system controls in B-Side's orange, and each setting with a small icon in
/// one of the Vibe colours, as System Settings has them.
struct SettingsView: View {
    enum Tab: String, CaseIterable {
        case general, appearance, playback, account, diagnostics
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
private struct ThinScrollers: NSViewRepresentable {
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
private struct SettingLabel: View {
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

private struct AccountSettings: View {
    @EnvironmentObject private var player: PlayerController
    @State private var confirmingSignOut = false

    var body: some View {
        Form {
            Section {
                switch player.account {
                case .unknown:
                    LabeledContent("YouTube Music", value: "Checking…")
                case .signedOut:
                    LabeledContent("YouTube Music", value: "Not signed in")
                    Button("Sign In…") { player.showSignIn() }
                case .signedIn(let name, let handle, let photoURL):
                    HStack(spacing: Theme.Space.s) {
                        AsyncImage(url: photoURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: Theme.Size.avatar, height: Theme.Size.avatar)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(name.isEmpty ? "YouTube Music" : name)
                            Text(handle.isEmpty ? "Signed in" : handle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .textSelection(.enabled)
                        Spacer()
                        Button("Sign Out…") { confirmingSignOut = true }
                    }
                    .padding(.vertical, Theme.Space.xxs)
                }
            } footer: {
                Text("You sign in on Google's own page. B-Side never sees your password.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .background(ThinScrollers())
        .confirmationDialog("Sign out of YouTube Music?", isPresented: $confirmingSignOut) {
            Button("Sign Out", role: .destructive) { player.signOut() }
        } message: {
            Text("Playback stops, and the cookies and caches B-Side keeps for YouTube Music are removed.")
        }
    }
}

private struct PlaybackSettings: View {
    @EnvironmentObject private var player: PlayerController
    @AppStorage(Keys.forceAudioOnly) private var audioOnly = true
    @AppStorage(Keys.nativeNowPlaying) private var nativeNowPlaying = true
    @AppStorage(Keys.reloadWhenPaused) private var reloadWhenPaused = false
    @AppStorage(Keys.reloadAfterMinutes) private var reloadAfterMinutes = 5

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $audioOnly) { SettingLabel(title: "Audio only", symbol: "waveform", colour: 2) }
                    .onChange(of: audioOnly) { player.applyPageSettings() }
            } footer: {
                Text("Plays the song version of a track when there is one. Videos play at the lowest quality. Uses less memory; changing it restarts the track where it was.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(isOn: $nativeNowPlaying) {
                    SettingLabel(title: "Media keys and Now Playing", symbol: "playpause.fill", colour: 7)
                }
                    .onChange(of: nativeNowPlaying) { player.applyNowPlayingSetting() }
            } footer: {
                Text("Play, pause and skip from the keyboard, and the track in Control Center.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(isOn: $reloadWhenPaused) {
                    SettingLabel(title: "Unload the player when paused", symbol: "memorychip", colour: 4)
                }
                Stepper("After \(reloadAfterMinutes) min", value: $reloadAfterMinutes, in: 1...120)
                    .disabled(!reloadWhenPaused)
            } footer: {
                Text("Frees most of the memory. The next Play loads the player again at the same position.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .background(ThinScrollers())
    }
}

/// How B-Side starts and what it tells you.
private struct GeneralSettings: View {
    var body: some View {
        Form {
            OpenAtLogin()
            TrackNotifications()
            AboutSection()
        }
        .formStyle(.grouped)
        .background(ThinScrollers())
    }
}

/// Who made B-Side, where to find them, and the version: a little warmth
/// at the end of General.
private struct AboutSection: View {
    var body: some View {
        Section {
            HStack(alignment: .top, spacing: Theme.Space.s) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: Theme.Size.aboutIcon, height: Theme.Size.aboutIcon)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text("B-Side")
                        .font(Theme.Text.title)
                    Text("A free, open-source and lightning-fast YouTube Music player for the Mac. Put on something good and enjoy.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Theme.Space.xxs) {
                        Text("\(Self.version) · With love by")
                            .foregroundStyle(.secondary)
                        Link("Anhile", destination: URL(string: "https://anhile.com")!)
                            .foregroundStyle(Theme.Colors.accentText)
                            .pointingHand()
                            .help("anhile.com")
                    }
                }
            }
            .padding(.vertical, Theme.Space.xxs)
        }
    }

    /// "Version 0.0.1 (1)": the version and the build.
    private static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }
}

/// Light or dark, and the size of everything in the window.
private struct AppearanceSettings: View {
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

/// Reads the system's Login Items each time Settings appear, since the user
/// can change it there too.
private struct OpenAtLogin: View {
    @State private var status = LoginItem.status
    @State private var failure: String?

    private var isOn: Binding<Bool> {
        Binding {
            status == .enabled || status == .requiresApproval
        } set: { on in
            do {
                try LoginItem.set(on)
                failure = nil
            } catch {
                failure = error.localizedDescription
            }
            status = LoginItem.status
        }
    }

    var body: some View {
        Section {
            Toggle(isOn: isOn) { SettingLabel(title: "Open at login", symbol: "power", colour: 0) }
            if status == .requiresApproval {
                LabeledContent("Waiting for your approval in Login Items") {
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            if let failure {
                Text(failure)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("B-Side starts in the menu bar, without its window, so the Play key and AirPods start B-Side instead of Apple Music.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .onAppear { status = LoginItem.status }
    }
}

/// Turning it on asks macOS for permission the first time. When macOS says
/// no, the toggle goes back off and points to System Settings.
private struct TrackNotifications: View {
    @AppStorage(Keys.notifyTrack) private var notify = false
    @State private var denied = false

    var body: some View {
        Section {
            Toggle(isOn: $notify) { SettingLabel(title: "Notify when a track starts", symbol: "bell.badge.fill", colour: 5) }
                .onChange(of: notify) {
                    guard notify else { return }
                    Task {
                        let allowed = await TrackNotifier.shared.requestPermission()
                        denied = !allowed
                        if !allowed { notify = false }
                    }
                }
            if denied {
                LabeledContent("Notifications are off for B-Side") {
                    Button("Open Notifications") {
                        NSWorkspace.shared.open(Self.systemSettings)
                    }
                }
            }
        } footer: {
            Text("The track's name and artwork, while B-Side is in the background. Clicking it opens Now Playing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .task {
            // Permission can be taken back in System Settings at any time.
            if notify, !(await TrackNotifier.shared.isAllowed()) {
                notify = false
                denied = true
            }
        }
    }

    private static let systemSettings =
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
}

private struct DiagnosticsSettings: View {
    @EnvironmentObject private var player: PlayerController
    @State private var log: [String] = []

    var body: some View {
        Form {
            Section("Memory: \(player.totalMegabytes, specifier: "%.0f") MB") {
                ForEach(player.processes) { process in
                    LabeledContent("\(process.name) (\(String(process.pid)))") {
                        Text("\(process.megabytes, specifier: "%.0f") MB").monospacedDigit()
                    }
                }
            }
            Section("Event log") {
                ScrollView {
                    Text(log.map(Self.short).joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: Theme.Size.logHeight)
                HStack {
                    Button("Refresh") { log = EventLog.tail(lines: 40) }
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([EventLog.file])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .background(ThinScrollers())
        .onAppear { log = EventLog.tail(lines: 40) }
    }

    /// `2026-09-30T12:51:57+04:00<TAB>D<TAB>track<TAB>…` becomes `12:51:57  track  …`.
    private static func short(_ line: String) -> String {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return line }
        let time = parts[0].split(separator: "T").last.map { $0.prefix(8) } ?? ""
        return ([String(time)] + parts.dropFirst(2).map(String.init)).joined(separator: "  ")
    }
}
