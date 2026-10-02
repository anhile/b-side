import SwiftUI

/// One job: pick one of my playlists, private ones included. A row opens
/// the playlist's tracks; its play button plays it straight away.
struct PlaylistsPage: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var navigation: Navigation
    @Environment(\.footerRoom) private var footerRoom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let likedMusic = Playlist(id: Tuning.likedMusicID, title: "Liked Music", subtitle: "Auto playlist")

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                if let playlist = player.openPlaylist {
                    PlaylistTracks(playlist: playlist)
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                } else {
                    library
                        .transition(reduceMotion ? .opacity : .move(edge: .leading))
                }
            }
            .clipped()
            bar
        }
        .animation(.easeInOut(duration: Theme.Motion.page), value: player.openPlaylist?.id)
    }

    private var library: some View {
        Group {
            if let blocked = blockingState(for: player) {
                blocked
                    .padding(.top, Theme.Size.pageBar)
                    .padding(.bottom, footerRoom)
            } else if player.account == .signedOut {
                EmptyState(symbol: "person.crop.circle", title: "Sign in for your playlists",
                           message: "Your playlists and Liked Music live in your YouTube Music account.",
                           actionTitle: "Sign In…") { player.showSignIn() }
                    .padding(.top, Theme.Size.pageBar)
                    .padding(.bottom, footerRoom)
            } else {
                content
            }
        }
    }

    /// One glass line right under the title bar, the width of the window.
    /// It stays while the lists slide under it; only what it says changes.
    /// The trailing button sits under the Playlists tab, in a slot as wide.
    private var bar: some View {
        ZStack {
            if let playlist = player.openPlaylist {
                tracksBar(playlist)
            } else {
                libraryBar
            }
        }
        .frame(height: Theme.Size.pageBar)
        .frame(maxWidth: .infinity)
        .barGlass(joined: .top)
    }

    /// Quiet: the tabs already say which page this is. The count is the one
    /// piece of information the rows cannot give.
    private var libraryBar: some View {
        HStack(spacing: 0) {
            Text(headerText)
                .font(Theme.Text.label)
                .foregroundStyle(Theme.Colors.textMuted)
            Spacer()
            IconButton(symbol: "plus", label: "New Playlist") {
                navigation.newPlaylist = NewPlaylistRequest()
            }
            .disabled(!player.account.isSignedIn || player.phase != .ready)
            .frame(width: Theme.Size.pageTabTarget)
            IconButton(symbol: "arrow.clockwise", label: "Refresh playlists") {
                player.loadPlaylists()
            }
            .disabled(!player.account.isSignedIn || player.phase != .ready)
            .frame(width: Theme.Size.pageTabTarget)
        }
        .padding(.leading, Theme.Space.m)
        .padding(.trailing, Theme.Space.xs)
        .transition(.opacity)
    }

    private func tracksBar(_ playlist: Playlist) -> some View {
        HStack(spacing: Theme.Space.xxs) {
            TransportButton(symbol: "chevron.left", label: "Back to playlists",
                            target: Theme.Size.pageTabTarget, color: Theme.Colors.textMuted) {
                player.closePlaylist()
            }
            Text(playlist.title)
                .font(Theme.Text.label)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(1)
                .help(playlist.title)
            Spacer(minLength: Theme.Space.xs)
            Button { player.play(playlist) } label: {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(FilledButtonStyle(compact: true))
            .disabled(player.tracksState != .loaded || player.tracks.isEmpty)
        }
        .padding(.horizontal, Theme.Space.xs)
        .transition(.opacity)
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
                .padding(.top, Theme.Size.pageBar)
                .padding(.bottom, footerRoom)
        case .failed(let reason):
            EmptyState(symbol: "exclamationmark.triangle", title: "Could not load playlists",
                       message: reason, actionTitle: "Try Again") { player.loadPlaylists() }
                .padding(.top, Theme.Size.pageBar)
                .padding(.bottom, footerRoom)
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
                    let isCurrent = player.source == .playlist(playlist.id) && player.hasTrack
                    HoverReveal(pinned: isCurrent) {
                        Button {
                            player.open(playlist)
                        } label: {
                            PlaylistRow(playlist: playlist, isCurrent: isCurrent, subtitle: player.subtitle(of: playlist))
                        }
                        .buttonStyle(RowButtonStyle())
                        .help("Show the tracks")
                    } control: {
                        playButton(for: playlist, isCurrent: isCurrent)
                            .padding(.trailing, Theme.Space.xxs)
                    }
                }
            }
            // The hover shape sits 8 inside the window edge, and the row's own
            // padding brings its content to the 16 window padding.
            .padding(.horizontal, Theme.Space.xs)
            .padding(.vertical, Theme.Space.xxs)
            .background(OverlayScrollers())
        }
        .contentMargins(.top, Theme.Size.pageBar, for: .scrollContent)
        .contentMargins(.top, Theme.Size.pageBar, for: .scrollIndicators)
        .contentMargins(.bottom, footerRoom, for: .scrollContent)
        .contentMargins(.bottom, footerRoom, for: .scrollIndicators)
    }
}

extension PlaylistsPage {
    /// Plays the playlist from the top; on the one that plays, pauses and
    /// resumes it instead.
    fileprivate func playButton(for playlist: Playlist, isCurrent: Bool) -> some View {
        let pauses = isCurrent && player.state.isPlaying
        return TransportButton(symbol: pauses ? "pause.fill" : "play.fill",
                               label: pauses ? "Pause" : "Play \(playlist.title)",
                               target: Theme.Size.artworkSmall,
                               color: isCurrent ? Theme.Colors.accentText : Theme.Colors.textMuted) {
            isCurrent ? player.togglePlayPause() : player.play(playlist)
        }
    }
}

struct PlaylistRow: View {
    let playlist: Playlist
    let isCurrent: Bool
    /// The subtitle as shown: without the author when it is the user.
    var subtitle: String

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
                    .foregroundStyle(isCurrent ? Theme.Colors.accentText : Theme.Colors.text)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.Text.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Space.xs)
            // Room for the play button that lies over the row.
            Color.clear.frame(width: Theme.Size.artworkSmall) // tokens-ok: empty room, not a colour
        }
        .padding(.horizontal, Theme.Space.xs)
        .frame(height: Theme.Size.rowHeight)
        .contentShape(Rectangle())
    }
}

/// A row with a control at its end, over the row so the row's hover spans
/// it, shown only under the pointer, or always while `pinned` (the playing
/// one keeps its pause button).
struct HoverReveal<Content: View, Control: View>: View {
    var pinned = false
    @ViewBuilder let content: Content
    @ViewBuilder let control: Control

    @State private var hovering = false

    var body: some View {
        content
            .overlay(alignment: .trailing) {
                control
                    .opacity(hovering || pinned ? 1 : 0)
                    .allowsHitTesting(hovering || pinned)
            }
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: Theme.Motion.feedback), value: hovering)
    }
}

/// A list row that is a button: `surface` under the pointer and while
/// pressed, nothing otherwise. No separators; the 44 rhythm groups them.
struct RowButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pointingHand()
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
    /// Round artwork, for a list of artists.
    var round = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<6) { index in
                HStack(spacing: Theme.Space.xs) {
                    RoundedRectangle(cornerRadius: round ? Theme.Size.artworkSmall / 2 : Theme.Radius.s)
                        .fill(Theme.Colors.surface)
                        .frame(width: Theme.Size.artworkSmall, height: Theme.Size.artworkSmall)
                    VStack(alignment: .leading, spacing: Theme.Size.skeletonGap) {
                        Capsule().fill(Theme.Colors.surface)
                            .frame(width: Theme.Size.skeletonTitle - CGFloat(index % 3) * Theme.Space.l,
                                   height: Theme.Size.skeletonLine)
                        Capsule().fill(Theme.Colors.surface)
                            .frame(width: Theme.Size.skeletonCaption - CGFloat(index % 2) * Theme.Space.l,
                                   height: Theme.Size.skeletonCaptionLine)
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
        .accessibilityLabel("Loading")
    }
}

/// Square artwork, loaded at the size it is shown.
struct Artwork: View {
    let url: URL?
    let size: CGFloat
    var radius = Theme.Radius.s
    var placeholder = "music.note"

    var body: some View {
        AsyncImage(url: url?.withoutBars) { image in
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

/// One playlist's tracks. Back leads to the library; Play plays it from the
/// top; a track plays the playlist from that track. More tracks load as the
/// list nears its end.
struct PlaylistTracks: View {
    let playlist: Playlist

    @EnvironmentObject private var player: PlayerController
    @Environment(\.footerRoom) private var footerRoom

    /// The page's bar above names the playlist and holds Back and Play.
    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        switch player.tracksState {
        case .idle, .loading:
            SkeletonList()
                .padding(.top, Theme.Size.pageBar)
                .padding(.bottom, footerRoom)
        case .failed(let reason):
            EmptyState(symbol: "exclamationmark.triangle", title: "Could not load the tracks",
                       message: reason, actionTitle: "Try Again") { player.retryTracks() }
                .padding(.top, Theme.Size.pageBar)
                .padding(.bottom, footerRoom)
        case .loaded where player.tracks.isEmpty:
            EmptyState(symbol: "music.note.list", title: "No tracks",
                       message: "This playlist is empty, or its tracks are not available.")
                .padding(.top, Theme.Size.pageBar)
                .padding(.bottom, footerRoom)
        case .loaded:
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(player.tracks) { track in
                    Button {
                        player.playOpenPlaylist(from: track)
                    } label: {
                        TrackRow(track: track, isCurrent: isCurrent(track), isPlaying: player.state.isPlaying)
                    }
                    .buttonStyle(RowButtonStyle())
                    .help(track.title)
                    .contextMenu {
                        TrackMenu(videoID: track.videoID, artist: track.artist, artistID: track.artistID,
                                  albumID: track.albumID, liked: track.liked) {
                            if track.removable || player.canEditOpenPlaylist, !track.setVideoID.isEmpty,
                               let playlist = player.openPlaylist {
                                Button(role: .destructive) { player.remove(track, from: playlist) } label: {
                                    Label("Remove from Playlist", systemImage: "minus.circle")
                                }
                            }
                        }
                    }
                    .onAppear {
                        if track.index >= player.tracks.count - Self.loadMoreAhead { player.loadMoreTracks() }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.xs)
            .padding(.vertical, Theme.Space.xxs)
            .background(OverlayScrollers())
        }
        .contentMargins(.top, Theme.Size.pageBar, for: .scrollContent)
        .contentMargins(.top, Theme.Size.pageBar, for: .scrollIndicators)
        .contentMargins(.bottom, footerRoom, for: .scrollContent)
        .contentMargins(.bottom, footerRoom, for: .scrollIndicators)
    }

    /// Rows from the end at which the next page is asked for.
    private static let loadMoreAhead = 5

    private func isCurrent(_ track: Track) -> Bool {
        player.source == .playlist(playlist.id) && player.state.videoID == track.videoID
    }
}

struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Artwork(url: track.artworkURL, size: Theme.Size.artworkSmall)
            VStack(alignment: .leading, spacing: 0) {
                Text(track.title.isEmpty ? "Untitled" : track.title)
                    .font(Theme.Text.body)
                    .foregroundStyle(isCurrent ? Theme.Colors.accentText : Theme.Colors.text)
                    .lineLimit(1)
                if !track.artist.isEmpty {
                    Text(track.artist)
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
