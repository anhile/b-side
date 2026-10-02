import SwiftUI

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
            MainWindow.startInMenuBar()
            Task { @MainActor in
                await Snapshots.render(into: URL(fileURLWithPath: folder))
                Settings.clearScratch()
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
