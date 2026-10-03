import SwiftUI

/// One line under Vibe and Playlists: what plays, Pause and Next; in a
/// window wide enough, Previous before them and Like after. The line
/// itself leads to the Now Playing page. When a vibe or a playlist plays,
/// its name slides up under the track: a vibe in its own colour, a
/// playlist, an album or a track's radio in the accent.
struct NowPlayingStrip: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var navigation: Navigation
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let open: () -> Void
    @State private var width: CGFloat = 0

    private var wide: Bool { width >= Theme.Size.stripWide }

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Button(action: open) {
                HStack(spacing: Theme.Space.xs) {
                    Artwork(url: player.state.artworkURL, size: Theme.Size.artworkStrip, radius: Theme.Radius.nested)
                    VStack(alignment: .leading, spacing: 0) {
                        MarqueeText(text: line, font: Theme.Text.body, color: Theme.Colors.text)
                        if player.state.isAd, player.state.adLeft >= 0 {
                            AdCountdown(font: Theme.Text.caption)
                        } else if player.showsBuffering {
                            Text("Buffering…")
                                .font(Theme.Text.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                        } else if let label = player.sourceLabel {
                            sourceLine(label)
                                .id(label)
                                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .clipped()
                    .animation(.snappy(duration: Theme.Motion.page), value: player.sourceLabel)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHand()
            .help("Now Playing")
            .contextMenu { trackMenu }
            .accessibilityLabel("Now Playing: \(line)" + (player.sourceLabel.map { ", from \($0.name)" } ?? ""))

            // As tall as the artwork, 4 inside the panel, like it.
            if wide {
                TransportButton(symbol: "backward.fill", label: "Previous", target: Theme.Size.artworkStrip) { player.previous() }
                    .disabled(!player.hasTrack)
            }
            TransportButton(symbol: player.state.isPlaying ? "pause.fill" : "play.fill",
                            label: player.state.isPlaying ? "Pause" : "Play",
                            glyph: Theme.Size.stripPlayGlyph, target: Theme.Size.artworkStrip) {
                player.togglePlayPause()
            }
            TransportButton(symbol: "forward.fill", label: "Next", target: Theme.Size.artworkStrip) { player.next() }
                .disabled(!player.state.hasNext)
            if wide, !player.state.isAd {
                TransportButton(symbol: player.state.isLiked ? "heart.fill" : "heart",
                                label: player.state.isLiked ? "Remove Like" : "Like", target: Theme.Size.artworkStrip,
                                color: player.state.isLiked ? Theme.Colors.accentText : Theme.Colors.textMuted) {
                    player.toggleLike()
                }
                .disabled(!player.hasTrack)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    /// Right-click: the menu every track has.
    private var trackMenu: some View {
        TrackMenu(videoID: player.state.isAd ? "" : player.state.videoID, title: player.state.title,
                  artist: player.state.artist,
                  artistID: player.state.artistID, albumID: player.state.albumID, liked: player.state.isLiked)
    }

    private func sourceLine(_ label: SourceLabel) -> some View {
        HStack(spacing: Theme.Space.xxs) {
            Image(systemName: label.symbol)
            Text(label.name)
        }
        .font(Theme.Text.caption)
        .fontWeight(.medium)
        .foregroundStyle(colour(of: label))
        .lineLimit(1)
    }

    /// A vibe's deep colour on the light glass, its light one on the dark.
    private func colour(of label: SourceLabel) -> Color {
        switch label.kind {
        case .vibe(let index):
            let swatch = VibePalette.swatches[index]
            return colorScheme == .dark ? swatch.light : swatch.deep
        case .playlist, .album, .artist, .radio:
            return Theme.Colors.accentText
        }
    }

    private var line: String {
        if player.state.isAd { return "Advertisement" }
        let title = player.state.title.isEmpty ? "Loading…" : player.state.title
        var artist = player.state.artist
        // Playing an artist's songs, the line under the track names them;
        // the others on a joint track stay.
        if let label = player.sourceLabel, label.kind == .artist {
            artist = artist.caseInsensitiveCompare(label.name) == .orderedSame ? "" : Self.names(in: artist)
                .filter { $0.caseInsensitiveCompare(label.name) != .orderedSame }
                .joined(separator: ", ")
        }
        return artist.isEmpty ? title : "\(title) — \(artist)"
    }

    /// "A, B & C feat. D" → A, B, C, D.
    private static func names(in artist: String) -> [String] {
        artist.replacingOccurrences(of: #"\s*(,|&|\bfeat\.?|\bft\.?)\s*"#, with: "\u{1F}",
                                    options: [.regularExpression, .caseInsensitive])
            .components(separatedBy: "\u{1F}")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
