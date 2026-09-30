import SwiftUI

/// One job: pick one of my playlists, private ones included.
struct PlaylistsPage: View {
    @EnvironmentObject private var player: PlayerController

    private let likedMusic = Playlist(id: Tuning.likedMusicID, title: "Liked Music", subtitle: "Auto playlist")

    var body: some View {
        VStack(spacing: 0) {
            header
            if let blocked = blockingState(for: player) {
                blocked
            } else {
                content
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Playlists")
                .font(.title3.weight(.semibold))
            Spacer()
            Button {
                player.loadPlaylists()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(!player.account.isSignedIn || player.phase != .ready)
            .help("Refresh")
            .accessibilityLabel("Refresh playlists")
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.xs)
    }

    @ViewBuilder
    private var content: some View {
        switch player.playlistsState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let reason):
            EmptyState(symbol: "exclamationmark.triangle", title: "Could not load playlists",
                       message: reason, actionTitle: "Try Again") { player.loadPlaylists() }
        case .loaded:
            list
        }
    }

    private var rows: [Playlist] {
        [likedMusic] + player.playlists.filter { $0.id != Tuning.likedMusicID }
    }

    private var list: some View {
        List(rows) { playlist in
            Button {
                player.play(playlist)
            } label: {
                PlaylistRow(playlist: playlist, isCurrent: player.source == .playlist(playlist.id),
                            isPlaying: player.state.isPlaying)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

struct PlaylistRow: View {
    let playlist: Playlist
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Artwork(url: playlist.artworkURL, size: Theme.Size.artworkSmall, placeholder: "music.note.list")
            VStack(alignment: .leading, spacing: 0) {
                Text(playlist.title)
                    .font(.body)
                    .lineLimit(1)
                if !playlist.subtitle.isEmpty {
                    Text(playlist.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Space.xs)
            if isCurrent {
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel(isPlaying ? "Playing" : "Paused")
            }
        }
        .frame(height: Theme.Size.rowHeight)
        .contentShape(Rectangle())
        .help(playlist.title)
    }
}

/// Square artwork, loaded at the size it is shown.
struct Artwork: View {
    let url: URL?
    let size: CGFloat
    var placeholder = "music.note"

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    Image(systemName: placeholder)
                        .foregroundStyle(.secondary)
                }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
        .accessibilityHidden(true)
    }
}
