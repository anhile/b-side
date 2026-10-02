import ServiceManagement
import SwiftUI

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
