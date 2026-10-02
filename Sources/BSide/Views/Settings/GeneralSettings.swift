import ServiceManagement
import SwiftUI

/// How B-Side starts and what it tells you.
struct GeneralSettings: View {
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
struct AboutSection: View {
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

/// Reads the system's Login Items each time Settings appear, since the user
/// can change it there too.
struct OpenAtLogin: View {
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
struct TrackNotifications: View {
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
