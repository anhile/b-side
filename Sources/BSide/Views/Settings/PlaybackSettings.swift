import ServiceManagement
import SwiftUI

/// Everything about the music: what plays, how it is controlled and
/// shown, the memory it takes, and where new vibes are read.
struct PlaybackSettings: View {
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
            } header: {
                Text("Sound")
            } footer: {
                Text("The song version of a track when there is one; videos at the lowest quality. Changing it restarts the track where it was.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(isOn: $nativeNowPlaying) {
                    SettingLabel(title: "Media keys and Control Center", symbol: "playpause.fill", colour: 7)
                }
                .onChange(of: nativeNowPlaying) { player.applyNowPlayingSetting() }
                TrackNotifications()
                MenuBarTrack()
            } header: {
                Text("Controls")
            } footer: {
                Text("A notification shows the track while B-Side is in the background; clicking it opens Now Playing. Long names in the menu bar are cut short.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(isOn: $reloadWhenPaused) {
                    SettingLabel(title: "Unload the player when paused", symbol: "memorychip", colour: 4)
                }
                Stepper("After \(reloadAfterMinutes) min", value: $reloadAfterMinutes, in: 1...120)
                    .disabled(!reloadWhenPaused)
            } header: {
                Text("Memory")
            } footer: {
                Text("Frees most of the memory. The next Play loads the player again at the same position.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VibeServerSections()
        }
        .formStyle(.grouped)
        .background(ThinScrollers())
    }
}
