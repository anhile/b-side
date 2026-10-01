import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case nowPlaying, vibe, playlists, explore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vibe: return "Vibes"
        case .playlists: return "Playlists"
        case .nowPlaying: return "Now Playing"
        case .explore: return "Explore"
        }
    }

    /// Command-1, 2, 3, in page order.
    var shortcutKey: Character {
        Character(String((Page.allCases.firstIndex(of: self) ?? 0) + 1))
    }

    var shortcutLabel: String { "⌘\(shortcutKey)" }

    /// Waves, a list with play, a record, a magnifier.
    var symbol: String {
        switch self {
        case .vibe: return "waveform"
        case .playlists: return "music.note.list"
        case .nowPlaying: return "opticaldisc"
        case .explore: return "magnifyingglass"
        }
    }
}

/// Which page of the main window is showing. Shared with the menu bar.
@MainActor
final class Navigation: ObservableObject {
    @Published var page: Page? = .nowPlaying
    /// Now Playing shows the lyrics in place of the artwork.
    @Published var showsLyrics = false
    /// The pages opened on Explore over the search, the last one showing.
    @Published private(set) var explorePath: [ExploreRoute] = []
    /// The page an Explore page was opened from, where Back returns from
    /// the first one; nil when it was opened on Explore itself.
    private var exploreReturn: Page?
    var exploreOrigin: Page? { exploreReturn }

    /// Opens an artist's or an album's page on Explore. From another page it
    /// starts over, and Back on it returns to that page.
    func open(_ route: ExploreRoute) {
        if let current = page, current != .explore {
            explorePath = [route]
            exploreReturn = current
        } else if explorePath.last != route {
            explorePath.append(route)
        }
        page = .explore
    }

    /// One page back on Explore: the one before, the search, or the page the
    /// first one was opened from.
    func exploreBack() {
        guard !explorePath.isEmpty else { return }
        explorePath.removeLast()
        if explorePath.isEmpty, let origin = exploreReturn {
            exploreReturn = nil
            page = origin
        }
    }

    /// Snapshots only.
    func setExplorePath(_ path: [ExploreRoute]) { explorePath = path }
}

/// A page Explore can open over its search.
enum ExploreRoute: Equatable {
    /// An artist, by browse ID ("UC…"), and the name to show while it loads.
    case artist(id: String, name: String)
    /// An album ("MPREb…") or a playlist ("VL…"), by browse ID.
    case collection(id: String, title: String)

    var title: String {
        switch self {
        case .artist(_, let name): return name
        case .collection(_, let title): return title
        }
    }

    /// The route to what a tile or a row stands for, if it opens a page.
    init?(_ item: MusicItem) {
        switch item.kind {
        case .artist where !item.browseID.isEmpty: self = .artist(id: item.browseID, name: item.title)
        case .album where !item.browseID.isEmpty, .playlist where !item.browseID.isEmpty:
            self = .collection(id: item.browseID, title: item.title)
        default: return nil
        }
    }
}

@main
struct BSideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var player = PlayerController()
    @StateObject private var navigation = Navigation()
    /// Changing the size builds the window again, at the new size.
    @AppStorage(Keys.uiSize) private var uiSize = UISize.compact.rawValue

    init() {
        Settings.register()
    }

    var body: some Scene {
        Window("B-Side", id: "main") {
            PlayerWindow()
                .environmentObject(player)
                .environmentObject(navigation)
                .id(uiSize)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(before: .toolbar) {
                ForEach(Page.allCases) { page in
                    Button(page.title) { navigation.page = page }
                        .keyboardShortcut(KeyEquivalent(page.shortcutKey), modifiers: .command)
                }
                Divider()
            }
            CommandMenu("Playback") {
                Button(player.state.isPlaying ? "Pause" : "Play") { player.togglePlayPause() }
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
                Picker("Repeat", selection: $player.repeatMode) {
                    ForEach(RepeatMode.allCases) { Text($0.title).tag($0) }
                }
                Button("Repeat: Next Mode") { player.repeatMode = player.repeatMode.next }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Play Vibe") { player.playVibe() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                    .disabled(player.vibeMood == nil)
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
    func applicationWillFinishLaunching(_ notification: Notification) {
        ThemeMode.apply()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        TrackNotifier.shared.install()
        if let folder = Settings.defaults.string(forKey: Keys.snapshot) {
            Task { @MainActor in
                await Snapshots.render(into: URL(fileURLWithPath: folder))
                NSApp.terminate(nil)
            }
            return
        }
        // At login B-Side is there for the media keys, not to be looked at.
        let atLogin = LoginItem.launchedAtLogin()
        let inMenuBar = atLogin || Settings.bool(Keys.startHidden)
        if inMenuBar {
            EventLog.write("start in the menu bar\t\(atLogin ? "login item" : "launch argument")")
            MainWindow.startInMenuBar()
        }
        MainWindow.launched(inMenuBar: inMenuBar)
    }

    /// Opening B-Side again from Finder, Spotlight or the Dock shows the
    /// window it started without.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        hasVisibleWindows || !MainWindow.show()
    }

    /// Playback must continue with every window closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        try? FileManager.default.removeItem(at: ProcessReporter.stateFile)
        EventLog.write("quit")
    }
}
