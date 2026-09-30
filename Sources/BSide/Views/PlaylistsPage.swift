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

    /// Quiet: the dots already say which page this is. The count is the one
    /// piece of information the rows cannot give.
    private var header: some View {
        HStack {
            Text(headerText)
                .font(Theme.Text.label)
                .foregroundStyle(Theme.Colors.textMuted)
            Spacer()
            IconButton(symbol: "arrow.clockwise", label: "Refresh playlists") {
                player.loadPlaylists()
            }
            .disabled(!player.account.isSignedIn || player.phase != .ready)
        }
        .frame(height: Theme.Size.pageDotTarget)
        .padding(.horizontal, Theme.Space.m)
        .padding(.bottom, Theme.Space.xxs)
    }

    private var headerText: String {
        guard player.playlistsState == .loaded, !player.playlists.isEmpty else { return "Playlists" }
        return "\(rows.count) playlists"
    }

    @ViewBuilder
    private var content: some View {
        switch player.playlistsState {
        case .idle, .loading:
            SkeletonList()
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
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(rows) { playlist in
                    Button {
                        player.play(playlist)
                    } label: {
                        PlaylistRow(playlist: playlist, isCurrent: player.source == .playlist(playlist.id),
                                    isPlaying: player.state.isPlaying)
                    }
                    .buttonStyle(RowButtonStyle())
                    .help(playlist.title)
                }
            }
            // The hover shape sits 8 inside the window edge, and the row's own
            // padding brings its content to the 16 window padding.
            .padding(.horizontal, Theme.Space.xs)
            .padding(.bottom, Theme.Space.xs)
            .background(OverlayScrollers())
        }
    }
}

struct PlaylistRow: View {
    let playlist: Playlist
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            if playlist.id == Tuning.likedMusicID {
                // Liked Music has no artwork of its own; the record stands in.
                Record(size: Theme.Size.artworkSmall, spinning: false)
            } else {
                Artwork(url: playlist.artworkURL, size: Theme.Size.artworkSmall, placeholder: "music.note.list")
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(playlist.title)
                    .font(Theme.Text.body)
                    .foregroundStyle(Theme.Colors.text)
                    .lineLimit(1)
                if !playlist.subtitle.isEmpty {
                    Text(playlist.subtitle)
                        .font(Theme.Text.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Space.xs)
            if isCurrent {
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                    .font(Theme.Text.body)
                    .foregroundStyle(Theme.Colors.accentText)
                    .accessibilityLabel(isPlaying ? "Playing" : "Paused")
            }
        }
        .padding(.horizontal, Theme.Space.xs)
        .frame(height: Theme.Size.rowHeight)
        .contentShape(Rectangle())
    }
}

/// A list row that is a button: `surface` under the pointer and while
/// pressed, nothing otherwise. No separators; the 44 rhythm groups them.
struct RowButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.s)
                    .fill(Theme.Colors.surface)
                    .opacity(configuration.isPressed || hovering ? 1 : 0)
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: Theme.Motion.feedback), value: hovering)
    }
}

/// Rows while the list loads: shapes in `surface` where artwork and text will
/// be, breathing slowly. Still with Reduce Motion.
struct SkeletonList: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<6) { index in
                HStack(spacing: Theme.Space.xs) {
                    RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .fill(Theme.Colors.surface)
                        .frame(width: Theme.Size.artworkSmall, height: Theme.Size.artworkSmall)
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Capsule().fill(Theme.Colors.surface)
                            .frame(width: Theme.Size.skeletonTitle - CGFloat(index % 3) * Theme.Space.l,
                                   height: Theme.Size.skeletonLine)
                        Capsule().fill(Theme.Colors.surface)
                            .frame(width: Theme.Size.skeletonCaption, height: Theme.Size.skeletonLine)
                    }
                    Spacer()
                }
                .padding(.horizontal, Theme.Space.xs)
                .frame(height: Theme.Size.rowHeight)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Space.xs)
        .opacity(dimmed ? Theme.Opacity.skeletonDim : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: Theme.Motion.breathe).repeatForever(autoreverses: true)) {
                dimmed = true
            }
        }
        .accessibilityLabel("Loading playlists")
    }
}

/// Square artwork, loaded at the size it is shown.
struct Artwork: View {
    let url: URL?
    let size: CGFloat
    var radius = Theme.Radius.s
    var placeholder = "music.note"

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle()
                .fill(Theme.Colors.surface)
                .overlay {
                    Image(systemName: placeholder)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .accessibilityHidden(true)
    }
}
