import SwiftUI

/// One line under Vibe and Playlists: what plays, Pause and Next. The line
/// itself leads to the Now Playing page.
struct NowPlayingStrip: View {
    @EnvironmentObject private var player: PlayerController
    let open: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Button(action: open) {
                HStack(spacing: Theme.Space.xs) {
                    Artwork(url: player.state.artworkURL, size: Theme.Size.artworkStrip, radius: Theme.Radius.nested)
                    MarqueeText(text: line, font: Theme.Text.body, color: Theme.Colors.text)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Now Playing")
            .accessibilityLabel("Now Playing: \(line)")

            // As tall as the artwork, 4 inside the panel, like it.
            TransportButton(symbol: player.state.isPlaying ? "pause.fill" : "play.fill",
                            label: player.state.isPlaying ? "Pause" : "Play",
                            glyph: Theme.Size.stripPlayGlyph, target: Theme.Size.artworkStrip) {
                player.togglePlayPause()
            }
            TransportButton(symbol: "forward.fill", label: "Next", target: Theme.Size.artworkStrip) { player.next() }
                .disabled(!player.state.hasNext)
        }
    }

    private var line: String {
        if player.state.isAd { return "Advertisement" }
        let title = player.state.title.isEmpty ? "Loading…" : player.state.title
        return player.state.artist.isEmpty ? title : "\(title) — \(player.state.artist)"
    }
}
