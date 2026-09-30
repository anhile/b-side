import SwiftUI

/// The standard macOS settings window: Command-comma, tabs, grouped forms.
struct SettingsView: View {
    var body: some View {
        TabView {
            AccountSettings()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            PlaybackSettings()
                .tabItem { Label("Playback", systemImage: "play.circle") }
            DiagnosticsSettings()
                .tabItem { Label("Diagnostics", systemImage: "gauge.with.dots.needle.33percent") }
        }
        .frame(width: Theme.Size.settingsWidth)
    }
}

private struct AccountSettings: View {
    @EnvironmentObject private var player: PlayerController
    @State private var confirmingSignOut = false

    var body: some View {
        Form {
            Section {
                LabeledContent("YouTube Music") {
                    switch player.account {
                    case .unknown:
                        Text("Checking…")
                    case .signedOut:
                        Text("Not signed in")
                    case .signedIn(let name, let handle):
                        // The channel handle, as in YouTube Music's own
                        // account menu. An account without a channel has
                        // none; then the name.
                        Text(!handle.isEmpty ? handle : !name.isEmpty ? name : "Signed in")
                            .textSelection(.enabled)
                    }
                }
                if player.account.isSignedIn {
                    Button("Sign Out…") { confirmingSignOut = true }
                } else {
                    Button("Sign In…") { player.showSignIn() }
                }
            } footer: {
                Text("You sign in on Google's own page. B-Side never sees your password.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
                Toggle("Audio only", isOn: $audioOnly)
                    .onChange(of: audioOnly) { player.applyPageSettings() }
            } footer: {
                Text("Plays the song version of a track when there is one, and videos at the lowest quality. Uses less memory. Changing it restarts the player; the track resumes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show in Now Playing and respond to media keys", isOn: $nativeNowPlaying)
                    .onChange(of: nativeNowPlaying) { player.applyNowPlayingSetting() }
            }
            Section {
                Toggle("Free memory when paused for a while", isOn: $reloadWhenPaused)
                Stepper("After \(reloadAfterMinutes) min", value: $reloadAfterMinutes, in: 1...120)
                    .disabled(!reloadWhenPaused)
            } footer: {
                Text("The player is unloaded and starts again on the next Play, at the same position.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DiagnosticsSettings: View {
    @EnvironmentObject private var player: PlayerController
    @State private var input = ""
    @State private var log: [String] = []

    var body: some View {
        Form {
            Section("Memory") {
                LabeledContent("Total") {
                    Text("\(player.totalMegabytes, specifier: "%.0f") MB").monospacedDigit()
                }
                ForEach(player.processes) { process in
                    LabeledContent("\(process.name) (\(String(process.pid)))") {
                        Text("\(process.megabytes, specifier: "%.0f") MB").monospacedDigit()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            Section("Player") {
                LabeledContent("Status") {
                    Text(player.status).lineLimit(2)
                }
                HStack {
                    TextField("Video ID, playlist ID, or URL", text: $input)
                        .onSubmit { player.load(input) }
                    Button("Play") { player.load(input) }
                        .disabled(input.isEmpty)
                }
                Button(player.isWebViewVisible ? "Hide Player Page" : "Show Player Page") {
                    player.isWebViewVisible ? player.hideWebView() : player.showWebView()
                }
            }
            Section("Event log") {
                ScrollView {
                    Text(log.joined(separator: "\n"))
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
        .onAppear { log = EventLog.tail(lines: 40) }
    }
}
