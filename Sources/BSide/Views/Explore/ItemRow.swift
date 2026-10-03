import AppKit
import SwiftUI

/// A row that does what its item does: a song plays (with its radio); an
/// album, a playlist or an artist opens. Albums and playlists also have a
/// play button at the end. Right-click: a song's menu, an album's artist.
struct ItemRowButton: View {
    let item: MusicItem
    /// Within an album or playlist: plays it from this track instead.
    var playFromHere: (() -> Void)?
    var number: Int?

    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var navigation: Navigation

    var body: some View {
        HoverReveal(playing: isCurrent && showsPlay ? player.state.isPlaying : nil) {
            Button(action: primary) {
                ItemRow(item: item, isCurrent: isCurrent, isPlaying: player.state.isPlaying,
                        number: number, roomForPlay: showsPlay)
            }
            // The song, album or playlist that plays keeps the hover's glass.
            .buttonStyle(RowButtonStyle(selected: isCurrent))
            .help(help)
        } control: {
            if showsPlay {
                TransportButton(symbol: isCurrent && player.state.isPlaying ? "pause.fill" : "play.fill",
                                label: "Play \(item.title)", target: Theme.Size.artworkSmall,
                                color: isCurrent ? Theme.Colors.accentText : Theme.Colors.textMuted) {
                    isCurrent ? player.togglePlayPause() : player.play(item)
                }
                .padding(.trailing, Theme.Space.xxs)
            }
        }
        .contextMenu {
            if item.kind == .song, !item.videoID.isEmpty {
                TrackMenu(videoID: item.videoID, title: item.title, artist: artistName, artistID: item.artistID,
                          albumID: item.albumID, liked: item.liked)
            } else if !item.artistID.isEmpty {
                Button { navigation.open(.artist(id: item.artistID, name: artistName)) } label: {
                    Label("Go to Artist", systemImage: "person")
                }
                .labelStyle(.titleAndIcon)
            }
        }
    }

    private var showsPlay: Bool {
        (item.kind == .album || item.kind == .playlist) && !item.playlistID.isEmpty
    }

    private var artistName: String {
        item.subtitle.components(separatedBy: " • ").first ?? item.title
    }

    private var help: String {
        switch item.kind {
        case .song: return playFromHere == nil ? "Play \(item.title) and its radio" : "Play from \(item.title)"
        case .album, .playlist: return "Show the tracks"
        case .artist: return "Show \(item.title)"
        }
    }

    private func primary() {
        if let playFromHere { return playFromHere() }
        if let route = ExploreRoute(item) {
            navigation.open(route)
        } else {
            player.play(item)
        }
    }

    private var isCurrent: Bool {
        guard player.hasTrack else { return false }
        if !item.videoID.isEmpty { return item.videoID == player.state.videoID }
        return !item.playlistID.isEmpty && player.source == .playlist(item.playlistID)
    }
}

/// Artwork (round for an artist, a track number in an album), title, and
/// what YouTube Music says under it; a track's length at the end.
struct ItemRow: View {
    let item: MusicItem
    let isCurrent: Bool
    let isPlaying: Bool
    var number: Int?
    var roomForPlay = false

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            if let number {
                Text("\(number)")
                    .font(Theme.Text.caption)
                    .monospacedDigit()
                    .foregroundStyle(isCurrent ? Theme.Colors.accentText : Theme.Colors.textMuted)
                    .frame(width: Theme.Size.artworkSmall)
            } else if item.kind == .artist {
                Artwork(url: item.artworkURL, size: Theme.Size.artworkSmall, radius: Theme.Size.artworkSmall / 2,
                        placeholder: "person.fill")
            } else {
                Artwork(url: item.artworkURL, size: Theme.Size.artworkSmall,
                        placeholder: item.kind == .song ? "music.note" : "music.note.list")
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(Theme.Text.body)
                    .foregroundStyle(isCurrent ? Theme.Colors.accentText : Theme.Colors.text)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(Theme.Text.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Space.xs)
            if isCurrent, !roomForPlay {
                PlayingMark(isPlaying: isPlaying)
            } else if !item.detail.isEmpty {
                Text(item.detail)
                    .font(Theme.Text.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textMuted)
            }
            if roomForPlay {
                // Room for the play button that lies over the row.
                Color.clear.frame(width: Theme.Size.artworkSmall) // tokens-ok: empty room, not a colour
            }
        }
        .padding(.horizontal, Theme.Space.xs)
        .frame(height: Theme.Size.rowHeight)
        .contentShape(Rectangle())
    }
}
