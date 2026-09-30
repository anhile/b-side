import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case vibe, playlists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vibe: return "Vibe"
        case .playlists: return "Playlists"
        }
    }
}

/// Which page of the main window is showing. Shared with the menu bar.
@MainActor
final class Navigation: ObservableObject {
    @Published var page: Page? = .vibe
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
                Button("Play Vibe") { player.playVibe() }
                    .keyboardShortcut("l", modifiers: .command)
                    .disabled(!player.account.isSignedIn)
            }
        }

        SwiftUI.Settings {
            SettingsView()
                .environmentObject(player)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Playback must continue with every window closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        try? FileManager.default.removeItem(at: ProcessReporter.stateFile)
        EventLog.write("quit")
    }
}
