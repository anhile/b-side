import AppKit
import SwiftUI

/// The status item's menu: the current track, transport, every Vibe tile and
/// playlist, and the way back to the window.
struct MenuBarMenu: View {
    @EnvironmentObject private var player: PlayerController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // A system menu cannot scroll text, so the lines are cut to a width.
        Text(Self.clip(titleLine))
        if !artistLine.isEmpty {
            Text(Self.clip(artistLine))
        }
        Divider()
        Button(player.state.isPlaying ? "Pause" : "Play") { player.togglePlayPause() }
        Button("Next") { player.next() }
            .disabled(!player.state.hasNext)
        Button("Previous") { player.previous() }
            .disabled(!player.hasTrack)
        Divider()
        Menu("Vibe") {
            ForEach(player.moods) { mood in
                Button(mood.name) { player.play(mood) }
            }
        }
        .disabled(!player.account.isSignedIn)
        Menu("Playlists") {
            Button("Liked Music") {
                player.play(Playlist(id: Tuning.likedMusicID, title: "Liked Music"))
            }
            ForEach(player.playlists.filter { $0.id != Tuning.likedMusicID }) { playlist in
                Button(playlist.title) { player.play(playlist) }
            }
        }
        .disabled(!player.account.isSignedIn)
        Divider()
        Button("Show B-Side") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit B-Side") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }

    private var titleLine: String {
        guard player.hasTrack else { return "Nothing playing" }
        if player.state.isAd { return "Advertisement" }
        return player.state.title.isEmpty ? "Loading…" : player.state.title
    }

    private var artistLine: String {
        player.hasTrack && !player.state.isAd ? player.state.artist : ""
    }

    private static let menuLineLength = 40

    private static func clip(_ text: String) -> String {
        text.count > menuLineLength ? text.prefix(menuLineLength - 1).trimmingCharacters(in: .whitespaces) + "…" : text
    }
}

/// The status item's icon: a record, drawn as a template so it follows the
/// menu bar's colour.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let disc = rect.insetBy(dx: 1, dy: 1)
            NSColor.black.setFill() // tokens-ok: a template image, colour comes from the menu bar
            NSBezierPath(ovalIn: disc).fill()
            NSColor.black.setStroke() // tokens-ok
            // Two grooves, cut out of the disc.
            for inset: CGFloat in [4, 6] {
                let groove = NSBezierPath(ovalIn: disc.insetBy(dx: inset, dy: inset))
                groove.lineWidth = 0.6
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                groove.stroke()
            }
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: disc.insetBy(dx: 7, dy: 7)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
