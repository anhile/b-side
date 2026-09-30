import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case nowPlaying, vibe, playlists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vibe: return "Vibe"
        case .playlists: return "Playlists"
        case .nowPlaying: return "Now Playing"
        }
    }

    /// Waves, a list with play, a record.
    var symbol: String {
        switch self {
        case .vibe: return "waveform"
        case .playlists: return "music.note.list"
        case .nowPlaying: return "opticaldisc"
        }
    }
}

/// Which page of the main window is showing. Shared with the menu bar.
@MainActor
final class Navigation: ObservableObject {
    @Published var page: Page? = .nowPlaying
}

@main
struct BSideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var player = PlayerController()
    @StateObject private var navigation = Navigation()

    init() {
        Settings.register()
    }

    var body: some Scene {
        Window("B-Side", id: "main") {
            PlayerWindow()
                .environmentObject(player)
                .environmentObject(navigation)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(before: .toolbar) {
                ForEach(Array(Page.allCases.enumerated()), id: \.element) { index, page in
                    Button(page.title) { navigation.page = page }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
                Divider()
            }
            CommandMenu("Playback") {
                Button(player.state.isPlaying ? "Pause" : "Play") { player.togglePlayPause() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Next") { player.next() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .disabled(!player.state.hasNext)
                Button("Previous") { player.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .disabled(!player.hasTrack)
                Divider()
                Button { player.toggleLike() } label: {
                    Label(player.state.isLiked ? "Remove Like" : "Like",
                          systemImage: player.state.isLiked ? "heart.slash" : "heart")
                }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(!player.hasTrack || player.state.isAd)
                Divider()
                Button("Play Vibe") { player.playVibe() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                    .disabled(!player.account.isSignedIn)
                Divider()
                Button("Increase Volume") { player.adjustVolume(by: PlayerController.volumeStep) }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Button("Decrease Volume") { player.adjustVolume(by: -PlayerController.volumeStep) }
                    .keyboardShortcut(.downArrow, modifiers: .command)
                Button(player.volume > 0 ? "Mute" : "Unmute") { player.toggleMute() }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            }
        }

        SwiftUI.Settings {
            SettingsView()
                .environmentObject(player)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let folder = Settings.defaults.string(forKey: Keys.snapshot) {
            Task { @MainActor in
                await Snapshots.render(into: URL(fileURLWithPath: folder))
                NSApp.terminate(nil)
            }
        }
    }

    /// Playback must continue with every window closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        try? FileManager.default.removeItem(at: ProcessReporter.stateFile)
        EventLog.write("quit")
    }
}
